//! An editable EXIF block: all IFDs with their decoded entries.
//!
//! All data is owned by an internal arena, so parsed input buffers can be
//! freed right after `parse`. Pointer tags (Exif/GPS/Interop IFD offsets and
//! thumbnail offset/length) are managed automatically and never appear as
//! entries; offsets are recomputed by `serialize`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Endian = std.builtin.Endian;

const types = @import("types.zig");
const tags = @import("tags.zig");
const IfdKind = types.IfdKind;
const Type = types.Type;
const Value = types.Value;
const Entry = types.Entry;
const Rational = types.Rational;
const Tag = tags.Tag;

const Exif = @This();

arena: std.heap.ArenaAllocator,
byte_order: Endian,
ifds: [IfdKind.count]std.ArrayList(Entry),
/// JPEG thumbnail bytes (referenced from IFD1), if any.
thumbnail: ?[]const u8 = null,

pub const ParseError = error{
    InvalidHeader,
    Truncated,
    TooManyIfds,
} || Allocator.Error;

pub const SerializeError = error{ValueTooLarge} || Allocator.Error;

/// Creates an empty EXIF block.
pub fn init(gpa: Allocator, byte_order: Endian) Exif {
    return .{
        .arena = .init(gpa),
        .byte_order = byte_order,
        .ifds = @splat(.empty),
    };
}

pub fn deinit(self: *Exif) void {
    self.arena.deinit();
    self.* = undefined;
}

fn allocator(self: *Exif) Allocator {
    return self.arena.allocator();
}

/// Entries of the given IFD, in file order.
pub fn entries(self: *const Exif, kind: IfdKind) []const Entry {
    return self.ifds[@backingInt(kind)].items;
}

fn indexOf(self: *const Exif, tag: Tag) ?usize {
    for (self.entries(tag.kind), 0..) |e, i| {
        if (e.tag == tag.num) return i;
    }
    return null;
}

/// Returns the tag's value, or null if absent.
pub fn get(self: *const Exif, tag: Tag) ?Value {
    const i = self.indexOf(tag) orelse return null;
    return self.entries(tag.kind)[i].value;
}

/// Returns an ASCII tag as text (without trailing NUL).
pub fn getString(self: *const Exif, tag: Tag) ?[]const u8 {
    return (self.get(tag) orelse return null).string();
}

/// Returns the first component of a byte/short/long tag.
pub fn getUint(self: *const Exif, tag: Tag) ?u32 {
    return (self.get(tag) orelse return null).uint();
}

/// Sets (adds or replaces) a tag. The value is copied.
pub fn set(self: *Exif, tag: Tag, value: Value) !void {
    if (isPointerTag(tag.kind, tag.num)) return error.ReservedTag;
    const owned = try value.dupe(self.allocator());
    const list = &self.ifds[@backingInt(tag.kind)];
    if (self.indexOf(tag)) |i| {
        list.items[i].value = owned;
    } else {
        try list.append(self.allocator(), .{ .tag = tag.num, .value = owned });
    }
}

/// Sets an ASCII tag. A NUL terminator is added.
pub fn setString(self: *Exif, tag: Tag, text: []const u8) !void {
    const buf = try self.allocator().alloc(u8, text.len + 1);
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    // `set` copies again; acceptable for small strings and keeps one code path.
    try self.set(tag, .{ .ascii = buf });
}

pub fn setShort(self: *Exif, tag: Tag, v: u16) !void {
    try self.set(tag, .{ .short = &.{v} });
}

pub fn setLong(self: *Exif, tag: Tag, v: u32) !void {
    try self.set(tag, .{ .long = &.{v} });
}

pub fn setRational(self: *Exif, tag: Tag, num: u32, den: u32) !void {
    try self.set(tag, .{ .rational = &.{.{ .num = num, .den = den }} });
}

/// Removes a tag. Returns true if it existed.
pub fn remove(self: *Exif, tag: Tag) bool {
    const i = self.indexOf(tag) orelse return false;
    _ = self.ifds[@backingInt(tag.kind)].orderedRemove(i);
    return true;
}

/// Removes every entry of an IFD (e.g. `.gps` to strip location data).
pub fn clear(self: *Exif, kind: IfdKind) void {
    self.ifds[@backingInt(kind)].clearRetainingCapacity();
    if (kind == .ifd1) self.thumbnail = null;
}

/// Removes the thumbnail and its IFD.
pub fn removeThumbnail(self: *Exif) void {
    self.clear(.ifd1);
}

/// Removes all entries from every IFD and the thumbnail, and frees their memory.
/// Values previously returned by `get`/`entries` become invalid.
/// Writing an empty block with `wexif.writeJpeg` removes the EXIF segment entirely.
pub fn clearAll(self: *Exif) void {
    _ = self.arena.reset(.retain_capacity);
    self.ifds = @splat(.empty);
    self.thumbnail = null;
}

/// True if there are no entries in any IFD and no thumbnail.
pub fn isEmpty(self: *const Exif) bool {
    if (self.thumbnail != null) return false;
    for (self.ifds) |list| if (list.items.len > 0) return false;
    return true;
}

// ---------------------------------------------------------------------------
// GPS helpers

pub const GpsCoordinates = struct {
    latitude: f64,
    longitude: f64,
    /// Meters; negative means below sea level.
    altitude: ?f64 = null,
};

/// Reads GPS coordinates in decimal degrees.
pub fn getGps(self: *const Exif) ?GpsCoordinates {
    const lat = dmsToDegrees(self.get(.gps_latitude) orelse return null) orelse return null;
    const lon = dmsToDegrees(self.get(.gps_longitude) orelse return null) orelse return null;
    const lat_ref = self.getString(.gps_latitude_ref) orelse "N";
    const lon_ref = self.getString(.gps_longitude_ref) orelse "E";
    var result: GpsCoordinates = .{
        .latitude = if (std.mem.startsWith(u8, lat_ref, "S")) -lat else lat,
        .longitude = if (std.mem.startsWith(u8, lon_ref, "W")) -lon else lon,
    };
    if (self.get(.gps_altitude)) |alt| switch (alt) {
        .rational => |r| if (r.len > 0) {
            const below = (self.getUint(.gps_altitude_ref) orelse 0) == 1;
            const m = r[0].toFloat();
            result.altitude = if (below) -m else m;
        },
        else => {},
    };
    return result;
}

/// Writes GPS coordinates (decimal degrees, altitude in meters).
pub fn setGps(self: *Exif, coords: GpsCoordinates) !void {
    if (!std.math.isFinite(coords.latitude) or @abs(coords.latitude) > 90) return error.InvalidCoordinate;
    if (!std.math.isFinite(coords.longitude) or @abs(coords.longitude) > 180) return error.InvalidCoordinate;

    if (self.get(.gps_version_id) == null) try self.set(.gps_version_id, .{ .byte = &.{ 2, 3, 0, 0 } });
    try self.setString(.gps_latitude_ref, if (coords.latitude < 0) "S" else "N");
    try self.set(.gps_latitude, .{ .rational = &degreesToDms(@abs(coords.latitude)) });
    try self.setString(.gps_longitude_ref, if (coords.longitude < 0) "W" else "E");
    try self.set(.gps_longitude, .{ .rational = &degreesToDms(@abs(coords.longitude)) });
    if (coords.altitude) |alt| {
        if (!std.math.isFinite(alt) or @abs(alt) > 1e6) return error.InvalidCoordinate;
        try self.set(.gps_altitude_ref, .{ .byte = &.{if (alt < 0) 1 else 0} });
        try self.setRational(.gps_altitude, @intFromFloat(@round(@abs(alt) * 100)), 100);
    }
}

fn dmsToDegrees(v: Value) ?f64 {
    const r = switch (v) {
        .rational => |r| r,
        else => return null,
    };
    if (r.len == 0) return null;
    var deg = r[0].toFloat();
    if (r.len > 1) deg += r[1].toFloat() / 60.0;
    if (r.len > 2) deg += r[2].toFloat() / 3600.0;
    return deg;
}

fn degreesToDms(deg: f64) [3]Rational {
    const d = @floor(deg);
    const m_full = (deg - d) * 60.0;
    const m = @floor(m_full);
    const s = (m_full - m) * 60.0;
    return .{
        .{ .num = @intFromFloat(d), .den = 1 },
        .{ .num = @intFromFloat(m), .den = 1 },
        .{ .num = @intFromFloat(@round(s * 10000)), .den = 10000 },
    };
}

// ---------------------------------------------------------------------------
// Parsing

const Reader = struct {
    data: []const u8,
    order: Endian,

    fn int(r: Reader, comptime T: type, off: u64) !T {
        const n = @sizeOf(T);
        if (off + n > r.data.len) return error.Truncated;
        const o: usize = @intCast(off);
        return std.mem.readInt(T, r.data[o..][0..n], r.order);
    }
};

fn isPointerTag(kind: IfdKind, tag: u16) bool {
    return switch (kind) {
        .ifd0 => tag == tags.exif_ifd_pointer or tag == tags.gps_ifd_pointer,
        .exif => tag == tags.interop_ifd_pointer,
        .ifd1 => tag == tags.thumbnail_offset or tag == tags.thumbnail_length,
        else => false,
    };
}

/// Parses a TIFF-structured EXIF block (the APP1 payload after "Exif\0\0").
pub fn parse(gpa: Allocator, data: []const u8) ParseError!Exif {
    if (data.len < 8) return error.InvalidHeader;
    const order: Endian = if (std.mem.eql(u8, data[0..2], "II"))
        .little
    else if (std.mem.eql(u8, data[0..2], "MM"))
        .big
    else
        return error.InvalidHeader;
    const r: Reader = .{ .data = data, .order = order };
    if (try r.int(u16, 2) != 42) return error.InvalidHeader;

    var self = Exif.init(gpa, order);
    errdefer self.deinit();

    var p: Pointers = .{};
    const ifd0_off = try r.int(u32, 4);
    const ifd1_off = try self.parseIfd(r, .ifd0, ifd0_off, &p);
    if (p.exif) |off| _ = try self.parseIfd(r, .exif, off, &p);
    if (p.gps) |off| _ = try self.parseIfd(r, .gps, off, &p);
    if (p.interop) |off| _ = try self.parseIfd(r, .interop, off, &p);
    if (ifd1_off != 0) {
        // A broken IFD1 should not make the whole block unreadable.
        if (self.parseIfd(r, .ifd1, ifd1_off, &p)) |_| {} else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => self.clear(.ifd1),
        }
    }

    // Only JPEG thumbnails are supported; strip-based thumbnails are dropped
    // because their offsets could not be rewritten correctly.
    if (self.indexOf(.{ .kind = .ifd1, .num = 0x0111 }) != null) {
        self.clear(.ifd1);
    } else if (p.thumb_offset != null and p.thumb_length != null) {
        const off = p.thumb_offset.?;
        const len = p.thumb_length.?;
        if (len > 0 and @as(u64, off) + len <= data.len) {
            self.thumbnail = try self.allocator().dupe(u8, data[off..][0..len]);
        }
    }
    return self;
}

const Pointers = struct {
    exif: ?u32 = null,
    gps: ?u32 = null,
    interop: ?u32 = null,
    thumb_offset: ?u32 = null,
    thumb_length: ?u32 = null,
    visited: [IfdKind.count]u32 = undefined,
    visited_len: usize = 0,
};

/// Parses one IFD and returns the offset of the next IFD (0 if none).
fn parseIfd(self: *Exif, r: Reader, kind: IfdKind, offset: u32, p: *Pointers) ParseError!u32 {
    for (p.visited[0..p.visited_len]) |v| if (v == offset) return error.InvalidHeader;
    if (p.visited_len == p.visited.len) return error.TooManyIfds;
    p.visited[p.visited_len] = offset;
    p.visited_len += 1;

    const n = try r.int(u16, offset);
    const list = &self.ifds[@backingInt(kind)];
    try list.ensureTotalCapacity(self.allocator(), n);

    for (0..n) |i| {
        const e: u64 = @as(u64, offset) + 2 + 12 * @as(u64, i);
        const tag = try r.int(u16, e);
        const ty: Type = @fromBackingInt(@intCast(try r.int(u16, e + 2)));
        const cnt = try r.int(u32, e + 4);
        const size = ty.size() orelse continue; // unknown type: skip
        const total = @as(u64, cnt) * size;
        const data_off: u64 = if (total <= 4) e + 8 else try r.int(u32, e + 8);
        if (data_off + total > r.data.len) continue; // corrupt entry: skip

        if (isPointerTag(kind, tag)) {
            const v = try r.int(u32, e + 8);
            switch (tag) {
                tags.exif_ifd_pointer => p.exif = v,
                tags.gps_ifd_pointer => p.gps = v,
                tags.interop_ifd_pointer => p.interop = v,
                tags.thumbnail_offset => p.thumb_offset = v,
                tags.thumbnail_length => p.thumb_length = v,
                else => unreachable,
            }
            continue;
        }

        const bytes = r.data[@intCast(data_off)..][0..@intCast(total)];
        const value = try decode(self.allocator(), ty, cnt, bytes, r.order);
        list.appendAssumeCapacity(.{ .tag = tag, .value = value });
    }
    const next_off = @as(u64, offset) + 2 + 12 * @as(u64, n);
    return r.int(u32, next_off) catch 0;
}

fn decode(gpa: Allocator, ty: Type, cnt: u32, bytes: []const u8, order: Endian) !Value {
    return switch (ty) {
        .byte => .{ .byte = try gpa.dupe(u8, bytes) },
        .ascii => .{ .ascii = try gpa.dupe(u8, bytes) },
        .undefined => .{ .undefined = try gpa.dupe(u8, bytes) },
        .sbyte => .{ .sbyte = @ptrCast(try gpa.dupe(u8, bytes)) },
        .short => .{ .short = try decodeInts(u16, gpa, cnt, bytes, order) },
        .sshort => .{ .sshort = try decodeInts(i16, gpa, cnt, bytes, order) },
        .long => .{ .long = try decodeInts(u32, gpa, cnt, bytes, order) },
        .slong => .{ .slong = try decodeInts(i32, gpa, cnt, bytes, order) },
        .float => blk: {
            const out = try gpa.alloc(f32, cnt);
            for (out, 0..) |*o, i| o.* = @bitCast(std.mem.readInt(u32, bytes[i * 4 ..][0..4], order));
            break :blk .{ .float = out };
        },
        .double => blk: {
            const out = try gpa.alloc(f64, cnt);
            for (out, 0..) |*o, i| o.* = @bitCast(std.mem.readInt(u64, bytes[i * 8 ..][0..8], order));
            break :blk .{ .double = out };
        },
        .rational => blk: {
            const out = try gpa.alloc(Rational, cnt);
            for (out, 0..) |*o, i| o.* = .{
                .num = std.mem.readInt(u32, bytes[i * 8 ..][0..4], order),
                .den = std.mem.readInt(u32, bytes[i * 8 + 4 ..][0..4], order),
            };
            break :blk .{ .rational = out };
        },
        .srational => blk: {
            const out = try gpa.alloc(types.SRational, cnt);
            for (out, 0..) |*o, i| o.* = .{
                .num = std.mem.readInt(i32, bytes[i * 8 ..][0..4], order),
                .den = std.mem.readInt(i32, bytes[i * 8 + 4 ..][0..4], order),
            };
            break :blk .{ .srational = out };
        },
        _ => unreachable,
    };
}

fn decodeInts(comptime T: type, gpa: Allocator, cnt: u32, bytes: []const u8, order: Endian) ![]T {
    const out = try gpa.alloc(T, cnt);
    const n = @sizeOf(T);
    for (out, 0..) |*o, i| o.* = std.mem.readInt(T, bytes[i * n ..][0..n], order);
    return out;
}

// ---------------------------------------------------------------------------
// Serialization

const max_size = std.math.maxInt(u32);

/// Encodes the block as TIFF data (without the "Exif\0\0" prefix).
/// Caller owns the returned memory.
pub fn serialize(self: *const Exif, gpa: Allocator) SerializeError![]u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const tmp = arena.allocator();

    const has_interop = self.entries(.interop).len > 0;
    const has_exif = self.entries(.exif).len > 0 or has_interop;
    const has_gps = self.entries(.gps).len > 0;
    const has_ifd1 = self.entries(.ifd1).len > 0 or self.thumbnail != null;

    // Working copies including pointer entries whose values are patched below.
    var lists: [IfdKind.count]std.ArrayList(Entry) = @splat(.empty);
    for (&lists, 0..) |*l, i| try l.appendSlice(tmp, self.ifds[i].items);

    const ptr_exif = try addPointer(tmp, &lists[@backingInt(IfdKind.ifd0)], tags.exif_ifd_pointer, has_exif);
    const ptr_gps = try addPointer(tmp, &lists[@backingInt(IfdKind.ifd0)], tags.gps_ifd_pointer, has_gps);
    const ptr_interop = try addPointer(tmp, &lists[@backingInt(IfdKind.exif)], tags.interop_ifd_pointer, has_interop);
    const has_thumb = self.thumbnail != null;
    const ptr_thumb = try addPointer(tmp, &lists[@backingInt(IfdKind.ifd1)], tags.thumbnail_offset, has_thumb);
    const ptr_thumb_len = try addPointer(tmp, &lists[@backingInt(IfdKind.ifd1)], tags.thumbnail_length, has_thumb);

    for (&lists) |*l| std.mem.sort(Entry, l.items, {}, lessThan);

    // Layout: header, IFD0, Exif, Interop, GPS, IFD1, thumbnail.
    const order = [_]IfdKind{ .ifd0, .exif, .interop, .gps, .ifd1 };
    const present = [_]bool{ true, has_exif, has_interop, has_gps, has_ifd1 };
    var offsets: [IfdKind.count]u32 = @splat(0);
    var pos: u64 = 8;
    for (order, present) |kind, here| {
        if (!here) continue;
        offsets[@backingInt(kind)] = @intCast(pos);
        pos += ifdSize(lists[@backingInt(kind)].items);
        if (pos > max_size) return error.ValueTooLarge;
    }
    const thumb_off = pos;
    if (self.thumbnail) |th| pos += th.len;
    if (pos > max_size) return error.ValueTooLarge;

    if (ptr_exif) |pv| pv[0] = offsets[@backingInt(IfdKind.exif)];
    if (ptr_gps) |pv| pv[0] = offsets[@backingInt(IfdKind.gps)];
    if (ptr_interop) |pv| pv[0] = offsets[@backingInt(IfdKind.interop)];
    if (ptr_thumb) |pv| pv[0] = @intCast(thumb_off);
    if (ptr_thumb_len) |pv| pv[0] = @intCast(self.thumbnail.?.len);

    const out = try gpa.alloc(u8, @intCast(pos));
    errdefer gpa.free(out);
    @memset(out, 0);
    const w: Writer = .{ .buf = out, .order = self.byte_order };

    @memcpy(out[0..2], if (self.byte_order == .little) "II" else "MM");
    w.int(u16, 2, 42);
    w.int(u32, 4, 8);

    for (order, present) |kind, here| {
        if (!here) continue;
        const next: u32 = if (kind == .ifd0) offsets[@backingInt(IfdKind.ifd1)] else 0;
        w.ifd(offsets[@backingInt(kind)], lists[@backingInt(kind)].items, next);
    }
    if (self.thumbnail) |th| @memcpy(out[@intCast(thumb_off)..][0..th.len], th);
    return out;
}

fn addPointer(tmp: Allocator, list: *std.ArrayList(Entry), tag: u16, needed: bool) !?[]u32 {
    if (!needed) return null;
    const v = try tmp.alloc(u32, 1);
    v[0] = 0;
    try list.append(tmp, .{ .tag = tag, .value = .{ .long = v } });
    return v;
}

fn lessThan(_: void, a: Entry, b: Entry) bool {
    return a.tag < b.tag;
}

fn ifdSize(list: []const Entry) u64 {
    var size: u64 = 2 + 12 * @as(u64, list.len) + 4;
    for (list) |e| {
        const n = e.value.byteSize();
        if (n > 4) size += n + (n & 1);
    }
    return size;
}

const Writer = struct {
    buf: []u8,
    order: Endian,

    fn int(w: Writer, comptime T: type, off: usize, v: T) void {
        std.mem.writeInt(T, w.buf[off..][0..@sizeOf(T)], v, w.order);
    }

    fn ifd(w: Writer, offset: u32, list: []const Entry, next: u32) void {
        var e: usize = offset;
        var data: usize = offset + 2 + 12 * list.len + 4;
        w.int(u16, e, @intCast(list.len));
        e += 2;
        for (list) |entry| {
            const size = entry.value.byteSize();
            w.int(u16, e, entry.tag);
            w.int(u16, e + 2, @backingInt(entry.value.typ()));
            w.int(u32, e + 4, entry.value.count());
            if (size <= 4) {
                w.value(e + 8, entry.value);
            } else {
                w.int(u32, e + 8, @intCast(data));
                w.value(data, entry.value);
                data += size + (size & 1);
            }
            e += 12;
        }
        w.int(u32, e, next);
    }

    fn value(w: Writer, off: usize, v: Value) void {
        switch (v) {
            .byte, .ascii, .undefined => |s| @memcpy(w.buf[off..][0..s.len], s),
            .sbyte => |s| @memcpy(w.buf[off..][0..s.len], @as([]const u8, @ptrCast(s))),
            .short => |s| for (s, 0..) |x, i| w.int(u16, off + i * 2, x),
            .sshort => |s| for (s, 0..) |x, i| w.int(i16, off + i * 2, x),
            .long => |s| for (s, 0..) |x, i| w.int(u32, off + i * 4, x),
            .slong => |s| for (s, 0..) |x, i| w.int(i32, off + i * 4, x),
            .float => |s| for (s, 0..) |x, i| w.int(u32, off + i * 4, @bitCast(x)),
            .double => |s| for (s, 0..) |x, i| w.int(u64, off + i * 8, @bitCast(x)),
            .rational => |s| for (s, 0..) |x, i| {
                w.int(u32, off + i * 8, x.num);
                w.int(u32, off + i * 8 + 4, x.den);
            },
            .srational => |s| for (s, 0..) |x, i| {
                w.int(i32, off + i * 8, x.num);
                w.int(i32, off + i * 8 + 4, x.den);
            },
        }
    }
};

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;

test "roundtrip all IFDs, both byte orders" {
    for ([_]Endian{ .little, .big }) |bo| {
        var ex = Exif.init(testing.allocator, bo);
        defer ex.deinit();

        try ex.setString(.make, "Wexif");
        try ex.setString(.model, "Model X with a long name");
        try ex.setShort(.orientation, 6);
        try ex.setRational(.exposure_time, 1, 250);
        try ex.set(.exposure_bias_value, .{ .srational = &.{.{ .num = -1, .den = 3 }} });
        try ex.set(.exif_version, .{ .undefined = "0232" });
        try ex.setString(.interoperability_index, "R98");
        try ex.setGps(.{ .latitude = 41.0082, .longitude = -28.9784, .altitude = -12.5 });
        try ex.set(Tag.compression.in(.ifd1), .{ .short = &.{6} });
        ex.thumbnail = "\xFF\xD8fake-thumb\xFF\xD9";

        const bytes = try ex.serialize(testing.allocator);
        defer testing.allocator.free(bytes);

        var back = try Exif.parse(testing.allocator, bytes);
        defer back.deinit();

        try testing.expectEqual(bo, back.byte_order);
        try testing.expectEqualStrings("Wexif", back.getString(.make).?);
        try testing.expectEqualStrings("Model X with a long name", back.getString(.model).?);
        try testing.expectEqual(@as(u32, 6), back.getUint(.orientation).?);
        try testing.expectEqual(@as(u32, 250), back.get(.exposure_time).?.rational[0].den);
        try testing.expectEqual(@as(i32, -1), back.get(.exposure_bias_value).?.srational[0].num);
        try testing.expectEqualStrings("0232", back.get(.exif_version).?.undefined);
        try testing.expectEqualStrings("R98", back.getString(.interoperability_index).?);
        try testing.expectEqualStrings(ex.thumbnail.?, back.thumbnail.?);

        const gps = back.getGps().?;
        try testing.expectApproxEqAbs(@as(f64, 41.0082), gps.latitude, 1e-6);
        try testing.expectApproxEqAbs(@as(f64, -28.9784), gps.longitude, 1e-6);
        try testing.expectApproxEqAbs(@as(f64, -12.5), gps.altitude.?, 1e-6);

        // Pointer tags are hidden from callers.
        try testing.expect(back.get(.{ .kind = .ifd0, .num = tags.exif_ifd_pointer }) == null);
        try testing.expectError(error.ReservedTag, back.setLong(.{ .kind = .ifd0, .num = tags.gps_ifd_pointer }, 1));
    }
}

test "clearAll" {
    var ex = Exif.init(testing.allocator, .little);
    defer ex.deinit();
    try ex.setString(.make, "Make");
    try ex.setRational(.exposure_time, 1, 60);
    try ex.setGps(.{ .latitude = 1, .longitude = 2 });
    try ex.setString(.interoperability_index, "R98");
    try ex.setShort(Tag.compression.in(.ifd1), 6);
    ex.thumbnail = "thumb";
    try testing.expect(!ex.isEmpty());

    ex.clearAll();
    try testing.expect(ex.isEmpty());
    for (std.meta.tags(IfdKind)) |k| try testing.expectEqual(@as(usize, 0), ex.entries(k).len);

    // Still usable after clearing.
    try ex.setString(.artist, "again");
    try testing.expectEqualStrings("again", ex.getString(.artist).?);
}

test "remove and clear" {
    var ex = Exif.init(testing.allocator, .little);
    defer ex.deinit();
    try ex.setString(.artist, "me");
    try ex.setGps(.{ .latitude = 1, .longitude = 2 });
    try testing.expect(ex.remove(.artist));
    try testing.expect(!ex.remove(.artist));
    ex.clear(.gps);

    const bytes = try ex.serialize(testing.allocator);
    defer testing.allocator.free(bytes);
    var back = try Exif.parse(testing.allocator, bytes);
    defer back.deinit();
    try testing.expect(back.getGps() == null);
    try testing.expectEqual(@as(usize, 0), back.entries(.ifd0).len);
}

test "parse rejects garbage and cycles without crashing" {
    try testing.expectError(error.InvalidHeader, Exif.parse(testing.allocator, "nope"));
    try testing.expectError(error.InvalidHeader, Exif.parse(testing.allocator, "XX\x2a\x00\x08\x00\x00\x00"));

    // IFD0 whose "next IFD" points back to itself.
    const cyc = "II\x2a\x00\x08\x00\x00\x00" ++ "\x00\x00" ++ "\x08\x00\x00\x00";
    var ex = try Exif.parse(testing.allocator, cyc);
    defer ex.deinit();
    try testing.expectEqual(@as(usize, 0), ex.entries(.ifd1).len);
}

test "parse is safe on truncated input" {
    var ex = Exif.init(testing.allocator, .big);
    defer ex.deinit();
    try ex.setString(.make, "Truncation test make");
    try ex.setGps(.{ .latitude = 10, .longitude = 20 });
    const bytes = try ex.serialize(testing.allocator);
    defer testing.allocator.free(bytes);

    for (0..bytes.len) |n| {
        if (Exif.parse(testing.allocator, bytes[0..n])) |parsed| {
            var p = parsed;
            p.deinit();
        } else |_| {}
    }
}
