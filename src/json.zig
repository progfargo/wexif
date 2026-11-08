//! JSON export of an EXIF block.
//!
//! Output shape:
//! ```json
//! {
//!   "byteOrder": "big",
//!   "ifd0": { "Make": "Canon", "Orientation": 6, "XResolution": 72 },
//!   "exif": { "ExposureTime": 0.004, "ISOSpeedRatings": 400 },
//!   "gps": { ... },
//!   "location": { "latitude": 41.0082, "longitude": 28.9784, "altitude": 35 },
//!   "thumbnailSize": 909
//! }
//! ```
//! Value mapping:
//! - Tags are keyed by their EXIF name, or `"0xNNNN"` if unknown.
//! - Text becomes a string. UserComment and the Windows XP* tags are decoded.
//! - A single number becomes a number, several become an array.
//! - Rationals become decimal numbers (`null` if the denominator is 0).
//! - Other binary data becomes a lowercase hex string, or `"(N bytes)"` when
//!   longer than `Options.max_binary_len`.
//! - Empty IFDs, `location` and `thumbnailSize` are omitted when absent.

const std = @import("std");
const Writer = std.Io.Writer;
const Stringify = std.json.Stringify;
const Endian = std.builtin.Endian;

const Exif = @import("Exif.zig");
const tags = @import("tags.zig");
const types = @import("types.zig");
const Tag = tags.Tag;
const IfdKind = types.IfdKind;
const Value = types.Value;

pub const Options = struct {
    whitespace: @FieldType(Stringify.Options, "whitespace") = .indent_2,
    /// Binary values longer than this (e.g. MakerNote) are summarized as "(N bytes)".
    max_binary_len: usize = 256,
};

/// Writes `exif` as JSON to `w`.
pub fn write(exif: *const Exif, w: *Writer, options: Options) Writer.Error!void {
    var s: Stringify = .{ .writer = w, .options = .{ .whitespace = options.whitespace } };
    try s.beginObject();
    try s.objectField("byteOrder");
    try s.write(@tagName(exif.byte_order));

    for (std.meta.tags(IfdKind)) |kind| {
        const list = exif.entries(kind);
        if (list.len == 0) continue;
        try s.objectField(@tagName(kind));
        try s.beginObject();
        for (list) |e| {
            const tag: Tag = .{ .kind = kind, .num = e.tag };
            if (tags.name(tag)) |name| {
                try s.objectField(name);
            } else {
                var buf: [6]u8 = undefined;
                try s.objectField(std.fmt.bufPrint(&buf, "0x{x:0>4}", .{e.tag}) catch unreachable);
            }
            try writeValue(&s, exif.byte_order, tag, e.value, options);
        }
        try s.endObject();
    }

    if (exif.getGps()) |g| {
        try s.objectField("location");
        try s.beginObject();
        // 7 decimals is ~1 cm and avoids float noise like 28.978399999999997.
        try s.objectField("latitude");
        try writeFloat(&s, round7(g.latitude));
        try s.objectField("longitude");
        try writeFloat(&s, round7(g.longitude));
        if (g.altitude) |alt| {
            try s.objectField("altitude");
            try writeFloat(&s, alt);
        }
        try s.endObject();
    }
    if (exif.thumbnail) |th| {
        try s.objectField("thumbnailSize");
        try s.write(th.len);
    }
    try s.endObject();
}

/// Returns `exif` as a JSON string. Caller owns the memory.
pub fn alloc(gpa: std.mem.Allocator, exif: *const Exif, options: Options) error{OutOfMemory}![]u8 {
    var aw: Writer.Allocating = .init(gpa);
    defer aw.deinit();
    write(exif, &aw.writer, options) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
}

fn writeValue(s: *Stringify, order: Endian, tag: Tag, v: Value, options: Options) Writer.Error!void {
    switch (v) {
        .ascii => |b| try writeText(s, std.mem.trimEnd(u8, b, "\x00")),
        .undefined => |b| {
            if (tag.eql(Tag.user_comment)) return writeUserComment(s, order, b, options);
            if (isPrintable(b)) return writeText(s, std.mem.trimEnd(u8, b, "\x00"));
            try writeBinary(s, b, options);
        },
        .byte => |b| {
            if (isXpTag(tag)) return writeUtf16(s, b, .little);
            try writeNumbers(s, b);
        },
        .sbyte => |x| try writeNumbers(s, x),
        .short => |x| try writeNumbers(s, x),
        .sshort => |x| try writeNumbers(s, x),
        .long => |x| try writeNumbers(s, x),
        .slong => |x| try writeNumbers(s, x),
        .float => |x| try writeList(s, x, writeFloat),
        .double => |x| try writeList(s, x, writeFloat),
        .rational => |x| try writeList(s, x, writeRational),
        .srational => |x| try writeList(s, x, writeRational),
    }
}

fn writeNumbers(s: *Stringify, items: anytype) Writer.Error!void {
    if (items.len == 1) return s.write(items[0]);
    try s.beginArray();
    for (items) |x| try s.write(x);
    try s.endArray();
}

fn writeList(s: *Stringify, items: anytype, comptime writeOne: anytype) Writer.Error!void {
    if (items.len == 1) return writeOne(s, items[0]);
    try s.beginArray();
    for (items) |x| try writeOne(s, x);
    try s.endArray();
}

fn writeFloat(s: *Stringify, x: anytype) Writer.Error!void {
    const f: f64 = @floatCast(x);
    if (!std.math.isFinite(f)) return s.write(null);
    try s.write(f);
}

fn round7(x: f64) f64 {
    return @round(x * 1e7) / 1e7;
}

fn writeRational(s: *Stringify, r: anytype) Writer.Error!void {
    if (r.den == 0) return s.write(null);
    try writeFloat(s, r.toFloat());
}

/// Writes text as a JSON string. Invalid UTF-8 is read as Latin-1.
fn writeText(s: *Stringify, text: []const u8) Writer.Error!void {
    if (std.unicode.utf8ValidateSlice(text)) return s.write(text);
    try s.beginWriteRaw();
    try s.writer.writeByte('"');
    for (text) |c| try writeCodepoint(s, c);
    try s.writer.writeByte('"');
    s.endWriteRaw();
}

/// Writes UTF-16 text (up to the first NUL) as a JSON string.
fn writeUtf16(s: *Stringify, bytes: []const u8, order: Endian) Writer.Error!void {
    try s.beginWriteRaw();
    try s.writer.writeByte('"');
    var i: usize = 0;
    while (i + 2 <= bytes.len) : (i += 2) {
        const unit = std.mem.readInt(u16, bytes[i..][0..2], order);
        if (unit == 0) break;
        var cp: u21 = unit;
        if (std.unicode.utf16IsHighSurrogate(unit)) {
            const low = if (i + 4 <= bytes.len) std.mem.readInt(u16, bytes[i + 2 ..][0..2], order) else 0;
            if (std.unicode.utf16IsLowSurrogate(low)) {
                cp = 0x10000 + ((@as(u21, unit) - 0xD800) << 10) + (low - 0xDC00);
                i += 2;
            } else cp = std.unicode.replacement_character;
        } else if (std.unicode.utf16IsLowSurrogate(unit)) {
            cp = std.unicode.replacement_character;
        }
        try writeCodepoint(s, cp);
    }
    try s.writer.writeByte('"');
    s.endWriteRaw();
}

fn writeCodepoint(s: *Stringify, cp: u21) Writer.Error!void {
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return;
    try Stringify.encodeJsonStringChars(buf[0..n], s.options, s.writer);
}

/// UserComment starts with an 8-byte character code followed by the text.
fn writeUserComment(s: *Stringify, order: Endian, b: []const u8, options: Options) Writer.Error!void {
    if (b.len < 8) return writeBinary(s, b, options);
    const code = b[0..8];
    const body = b[8..];
    if (std.mem.eql(u8, code, "ASCII\x00\x00\x00") or std.mem.allEqual(u8, code, 0)) {
        return writeText(s, std.mem.trimEnd(u8, body, "\x00 "));
    }
    if (std.mem.eql(u8, code, "UNICODE\x00")) return writeUtf16(s, body, order);
    try writeBinary(s, b, options);
}

fn writeBinary(s: *Stringify, b: []const u8, options: Options) Writer.Error!void {
    if (b.len > options.max_binary_len) {
        var buf: [32]u8 = undefined;
        return s.write(std.fmt.bufPrint(&buf, "({d} bytes)", .{b.len}) catch unreachable);
    }
    try s.beginWriteRaw();
    try s.writer.writeByte('"');
    for (b) |c| try s.writer.print("{x:0>2}", .{c});
    try s.writer.writeByte('"');
    s.endWriteRaw();
}

fn isPrintable(b: []const u8) bool {
    const t = std.mem.trimEnd(u8, b, "\x00");
    if (t.len == 0) return false;
    for (t) |c| if (!std.ascii.isPrint(c)) return false;
    return true;
}

fn isXpTag(tag: Tag) bool {
    return (tag.kind == .ifd0 or tag.kind == .ifd1) and tag.num >= 0x9C9B and tag.num <= 0x9C9F;
}

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;

test "json output parses and has the expected values" {
    var ex = Exif.init(testing.allocator, .big);
    defer ex.deinit();
    try ex.setString(.make, "Canon");
    try ex.setShort(.orientation, 6);
    try ex.set(.bits_per_sample, .{ .short = &.{ 8, 8, 8 } });
    try ex.setRational(.exposure_time, 1, 250);
    try ex.setRational(.f_number, 0, 0);
    try ex.set(.exposure_bias_value, .{ .srational = &.{.{ .num = -1, .den = 2 }} });
    try ex.set(.exif_version, .{ .undefined = "0232" });
    try ex.set(.components_configuration, .{ .undefined = &.{ 1, 2, 3, 0 } });
    const maker_note: [300]u8 = @splat(0xAB);
    try ex.set(.maker_note, .{ .undefined = &maker_note });
    try ex.set(.user_comment, .{ .undefined = "ASCII\x00\x00\x00Hello \"world\"" });
    try ex.set(.xp_title, .{ .byte = "C\x00a\x00f\x00\xe9\x00\x00\x00" }); // "Café" in UTF-16LE
    try ex.setString(.{ .kind = .exif, .num = 0xC0DE }, "custom");
    try ex.setString(.artist, "Ol\xe9"); // Latin-1, not UTF-8
    try ex.setGps(.{ .latitude = -33.5, .longitude = 151.25 });
    ex.thumbnail = "thumb";

    const out = try alloc(testing.allocator, &ex, .{});
    defer testing.allocator.free(out);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    const ifd0 = root.get("ifd0").?.object;
    const exif = root.get("exif").?.object;

    try testing.expectEqualStrings("big", root.get("byteOrder").?.string);
    try testing.expectEqualStrings("Canon", ifd0.get("Make").?.string);
    try testing.expectEqual(@as(i64, 6), ifd0.get("Orientation").?.integer);
    try testing.expectEqual(@as(usize, 3), ifd0.get("BitsPerSample").?.array.items.len);
    try testing.expectEqualStrings("Café", ifd0.get("XPTitle").?.string);
    try testing.expectEqualStrings("Olé", ifd0.get("Artist").?.string);
    try testing.expectEqual(@as(f64, 0.004), exif.get("ExposureTime").?.float);
    try testing.expect(exif.get("FNumber").? == .null);
    try testing.expectEqual(@as(f64, -0.5), exif.get("ExposureBiasValue").?.float);
    try testing.expectEqualStrings("0232", exif.get("ExifVersion").?.string);
    try testing.expectEqualStrings("01020300", exif.get("ComponentsConfiguration").?.string);
    try testing.expectEqualStrings("(300 bytes)", exif.get("MakerNote").?.string);
    try testing.expectEqualStrings("Hello \"world\"", exif.get("UserComment").?.string);
    try testing.expectEqualStrings("custom", exif.get("0xc0de").?.string);
    try testing.expectEqual(@as(f64, -33.5), root.get("location").?.object.get("latitude").?.float);
    try testing.expectEqual(@as(f64, 151.25), root.get("location").?.object.get("longitude").?.float);
    try testing.expectEqual(@as(i64, 5), root.get("thumbnailSize").?.integer);
    try testing.expect(root.get("interop") == null);
}

test "unicode user comment and empty exif" {
    var ex = Exif.init(testing.allocator, .little);
    defer ex.deinit();

    const empty = try alloc(testing.allocator, &ex, .{ .whitespace = .minified });
    defer testing.allocator.free(empty);
    try testing.expectEqualStrings("{\"byteOrder\":\"little\"}", empty);

    try ex.set(.user_comment, .{ .undefined = "UNICODE\x00\xac\x205\x00" }); // "€5" in UTF-16LE
    const out = try alloc(testing.allocator, &ex, .{ .whitespace = .minified });
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"byteOrder\":\"little\",\"exif\":{\"UserComment\":\"€5\"}}", out);
}
