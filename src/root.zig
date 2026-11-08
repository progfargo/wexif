//! wexif — read and edit EXIF metadata in JPEG files.
//!
//! ```zig
//! var exif = (try wexif.readJpeg(gpa, jpeg_bytes)) orelse wexif.Exif.init(gpa, .little);
//! defer exif.deinit();
//! try exif.setString(.artist, "Me");
//! try exif.setShort(.orientation, 1);
//! exif.clear(.gps);
//! const out = try wexif.writeJpeg(gpa, jpeg_bytes, &exif);
//! defer gpa.free(out);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Exif = @import("Exif.zig");
pub const tags = @import("tags.zig");
pub const Tag = tags.Tag;
pub const jpeg = @import("jpeg.zig");

const types = @import("types.zig");
pub const IfdKind = types.IfdKind;
pub const Type = types.Type;
pub const Value = types.Value;
pub const Entry = types.Entry;
pub const Rational = types.Rational;
pub const SRational = types.SRational;

/// Parses the EXIF block of a JPEG. Returns null if the image has none.
/// The result does not reference `data`.
pub fn readJpeg(gpa: Allocator, data: []const u8) !?Exif {
    const tiff = try jpeg.findExif(data) orelse return null;
    return try Exif.parse(gpa, tiff);
}

/// Returns a copy of `data` with its EXIF replaced by `exif`, or with the
/// EXIF segment removed when `exif` is null or empty. Caller owns the result.
pub fn writeJpeg(gpa: Allocator, data: []const u8, exif: ?*const Exif) ![]u8 {
    const ex = exif orelse return jpeg.replaceExif(gpa, data, null);
    if (ex.isEmpty()) return jpeg.replaceExif(gpa, data, null);
    const tiff = try ex.serialize(gpa);
    defer gpa.free(tiff);
    return jpeg.replaceExif(gpa, data, tiff);
}

/// Reads a JPEG file and parses its EXIF block.
pub fn readFile(gpa: Allocator, io: std.Io, path: []const u8) !?Exif {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_size));
    defer gpa.free(data);
    return readJpeg(gpa, data);
}

/// Rewrites `in_path` with the given EXIF (or none) into `out_path`.
/// `in_path` and `out_path` may be the same file.
pub fn writeFile(gpa: Allocator, io: std.Io, in_path: []const u8, out_path: []const u8, exif: ?*const Exif) !void {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .limited(max_file_size));
    defer gpa.free(data);
    const out = try writeJpeg(gpa, data, exif);
    defer gpa.free(out);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out });
}

pub const max_file_size = 1 << 30;

/// Parses a text value into the given type, e.g. for CLI input:
/// - ascii: the text as-is
/// - undefined/byte: raw text bytes, or hex like `0x30323332`
/// - integer types: comma-separated numbers (`1, 2, 3`)
/// - rationals: `num/den` or decimals (`1/250`, `2.8`), comma-separated
/// Memory is allocated with `gpa`; free it with an arena or `freeValue`.
pub fn parseValue(gpa: Allocator, ty: Type, text: []const u8) !Value {
    switch (ty) {
        .ascii => {
            const s = try gpa.alloc(u8, text.len + 1);
            @memcpy(s[0..text.len], text);
            s[text.len] = 0;
            return .{ .ascii = s };
        },
        .byte, .undefined => {
            const bytes = if (std.mem.startsWith(u8, text, "0x")) blk: {
                const hex = text[2..];
                if (hex.len % 2 != 0) return error.InvalidValue;
                const b = try gpa.alloc(u8, hex.len / 2);
                errdefer gpa.free(b);
                _ = std.fmt.hexToBytes(b, hex) catch return error.InvalidValue;
                break :blk b;
            } else try gpa.dupe(u8, text);
            return if (ty == .byte) .{ .byte = bytes } else .{ .undefined = bytes };
        },
        .short => return .{ .short = try parseList(u16, gpa, text) },
        .long => return .{ .long = try parseList(u32, gpa, text) },
        .sbyte => return .{ .sbyte = try parseList(i8, gpa, text) },
        .sshort => return .{ .sshort = try parseList(i16, gpa, text) },
        .slong => return .{ .slong = try parseList(i32, gpa, text) },
        .float => return .{ .float = try parseList(f32, gpa, text) },
        .double => return .{ .double = try parseList(f64, gpa, text) },
        .rational => return .{ .rational = try parseList(Rational, gpa, text) },
        .srational => return .{ .srational = try parseList(SRational, gpa, text) },
        _ => return error.InvalidValue,
    }
}

/// Frees a value returned by `parseValue`.
pub fn freeValue(gpa: Allocator, v: Value) void {
    switch (v) {
        inline else => |s| gpa.free(s),
    }
}

fn parseList(comptime T: type, gpa: Allocator, text: []const u8) ![]T {
    var list: std.ArrayList(T) = .empty;
    errdefer list.deinit(gpa);
    var it = std.mem.tokenizeAny(u8, text, ", ");
    while (it.next()) |tok| try list.append(gpa, try parseOne(T, tok));
    if (list.items.len == 0) return error.InvalidValue;
    return list.toOwnedSlice(gpa);
}

fn parseOne(comptime T: type, tok: []const u8) !T {
    switch (T) {
        Rational, SRational => {
            const I = @FieldType(T, "num");
            if (std.mem.indexOfScalar(u8, tok, '/')) |slash| {
                return .{
                    .num = std.fmt.parseInt(I, tok[0..slash], 10) catch return error.InvalidValue,
                    .den = std.fmt.parseInt(I, tok[slash + 1 ..], 10) catch return error.InvalidValue,
                };
            }
            const f = std.fmt.parseFloat(f64, tok) catch return error.InvalidValue;
            const den: I = 10000;
            const num = @round(f * den);
            if (!std.math.isFinite(num) or num < std.math.minInt(I) or num > std.math.maxInt(I))
                return error.InvalidValue;
            return .{ .num = @intFromFloat(num), .den = den };
        },
        f32, f64 => return std.fmt.parseFloat(T, tok) catch error.InvalidValue,
        else => return std.fmt.parseInt(T, tok, 0) catch error.InvalidValue,
    }
}

test {
    std.testing.refAllDecls(@This());
    _ = Exif;
    _ = tags;
    _ = jpeg;
}

test "readJpeg / writeJpeg roundtrip" {
    const gpa = std.testing.allocator;
    const img = "\xFF\xD8\xFF\xDA\x00\x03\x00scan\xFF\xD9";

    try std.testing.expect(try readJpeg(gpa, img) == null);

    var ex = Exif.init(gpa, .big);
    defer ex.deinit();
    try ex.setString(.artist, "Erdem");
    const out = try writeJpeg(gpa, img, &ex);
    defer gpa.free(out);

    var back = (try readJpeg(gpa, out)).?;
    defer back.deinit();
    try std.testing.expectEqualStrings("Erdem", back.getString(.artist).?);

    const stripped = try writeJpeg(gpa, out, null);
    defer gpa.free(stripped);
    try std.testing.expectEqualStrings(img, stripped);

    // An empty block removes the segment instead of writing an empty one.
    back.clearAll();
    const cleared = try writeJpeg(gpa, out, &back);
    defer gpa.free(cleared);
    try std.testing.expectEqualStrings(img, cleared);
    try std.testing.expect(try readJpeg(gpa, cleared) == null);
}

test "parseValue" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, (try parseValue(a, .short, "1, 2,3")).short);
    const r = (try parseValue(a, .rational, "1/250 2.8")).rational;
    try std.testing.expectEqual(@as(u32, 250), r[0].den);
    try std.testing.expectApproxEqAbs(@as(f64, 2.8), r[1].toFloat(), 1e-9);
    try std.testing.expectEqual(@as(i32, -1), (try parseValue(a, .srational, "-1/3")).srational[0].num);
    try std.testing.expectEqualStrings("0232", (try parseValue(a, .undefined, "0x30323332")).undefined);
    try std.testing.expectEqualStrings("hi\x00", (try parseValue(a, .ascii, "hi")).ascii);
    try std.testing.expectError(error.InvalidValue, parseValue(a, .short, "abc"));
    try std.testing.expectError(error.InvalidValue, parseValue(a, .rational, "-1/2"));
}
