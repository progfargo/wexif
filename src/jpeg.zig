//! Minimal JPEG segment handling: locate and replace the EXIF APP1 segment.
//! Image data is never decoded; everything except the EXIF segment is copied
//! byte for byte.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    NotJpeg,
    Truncated,
    ExifTooLarge,
} || Allocator.Error;

pub const exif_header = "Exif\x00\x00";

/// Max TIFF payload in a single APP1 segment (length field is u16 and includes itself).
pub const max_exif_size = 0xFFFF - 2 - exif_header.len;

const app0 = 0xE0;
const app1 = 0xE1;
const sos = 0xDA;
const eoi = 0xD9;

const Segment = struct {
    marker: u8,
    /// Whole segment including the FF marker and length.
    raw: []const u8,
    /// Payload after the length field.
    payload: []const u8,

    fn isExif(s: Segment) bool {
        return s.marker == app1 and std.mem.startsWith(u8, s.payload, exif_header[0..5]) and s.payload.len >= exif_header.len;
    }
};

/// Iterates over header segments up to (not including) SOS.
const Iterator = struct {
    data: []const u8,
    pos: usize = 2,
    /// Offset where SOS (or EOI / trailing data) begins once iteration stops.
    rest: usize = 0,

    fn init(data: []const u8) Error!Iterator {
        if (data.len < 4 or data[0] != 0xFF or data[1] != 0xD8) return error.NotJpeg;
        return .{ .data = data };
    }

    fn next(it: *Iterator) Error!?Segment {
        const d = it.data;
        while (true) {
            if (it.pos >= d.len) {
                it.rest = d.len;
                return null;
            }
            if (d[it.pos] != 0xFF) return error.NotJpeg;
            const start = it.pos;
            // Skip fill bytes.
            var p = it.pos;
            while (p < d.len and d[p] == 0xFF) p += 1;
            if (p >= d.len) return error.Truncated;
            const marker = d[p];
            p += 1;

            if (marker == sos or marker == eoi) {
                it.rest = start;
                return null;
            }
            // Standalone markers without a length field.
            if (marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7)) {
                it.pos = p;
                continue;
            }
            if (p + 2 > d.len) return error.Truncated;
            const len = std.mem.readInt(u16, d[p..][0..2], .big);
            if (len < 2 or p + len > d.len) return error.Truncated;
            it.pos = p + len;
            return .{ .marker = marker, .raw = d[start..it.pos], .payload = d[p + 2 .. it.pos] };
        }
    }
};

/// Returns the TIFF data of the first EXIF APP1 segment, or null if absent.
/// The returned slice points into `data`.
pub fn findExif(data: []const u8) Error!?[]const u8 {
    var it = try Iterator.init(data);
    while (try it.next()) |seg| {
        if (seg.isExif()) return seg.payload[exif_header.len..];
    }
    return null;
}

/// Returns a new JPEG with all EXIF segments removed and, if `tiff` is given,
/// a new EXIF APP1 segment inserted (after a leading JFIF APP0, if present).
/// Caller owns the returned memory.
pub fn replaceExif(gpa: Allocator, data: []const u8, tiff: ?[]const u8) Error![]u8 {
    if (tiff) |t| if (t.len > max_exif_size) return error.ExifTooLarge;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, data.len + if (tiff) |t| t.len + 10 else 0);
    out.appendSliceAssumeCapacity(data[0..2]);

    var it = try Iterator.init(data);
    var first = true;
    var inserted = false;
    while (try it.next()) |seg| {
        defer first = false;
        if (first and seg.marker == app0) {
            try out.appendSlice(gpa, seg.raw);
            continue;
        }
        if (!inserted) {
            try appendExif(gpa, &out, tiff);
            inserted = true;
        }
        if (seg.isExif()) continue;
        try out.appendSlice(gpa, seg.raw);
    }
    if (!inserted) try appendExif(gpa, &out, tiff);
    try out.appendSlice(gpa, data[it.rest..]);
    return out.toOwnedSlice(gpa);
}

fn appendExif(gpa: Allocator, out: *std.ArrayList(u8), tiff: ?[]const u8) !void {
    const t = tiff orelse return;
    const len: u16 = @intCast(2 + exif_header.len + t.len);
    try out.appendSlice(gpa, &.{ 0xFF, app1 });
    var len_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &len_buf, len, .big);
    try out.appendSlice(gpa, &len_buf);
    try out.appendSlice(gpa, exif_header);
    try out.appendSlice(gpa, t);
}

const testing = std.testing;

/// SOI, APP0 (JFIF), DQT-like segment, SOS + scan data, EOI.
const sample = "\xFF\xD8" ++
    "\xFF\xE0\x00\x07JFIF\x00" ++
    "\xFF\xDB\x00\x04\x01\x02" ++
    "\xFF\xDA\x00\x03\x00" ++ "scan\xFF\x00data" ++ "\xFF\xD9";

test "insert, find, replace and remove" {
    try testing.expect(try findExif(sample) == null);

    const with = try replaceExif(testing.allocator, sample, "TIFFDATA");
    defer testing.allocator.free(with);
    try testing.expectEqualStrings("TIFFDATA", (try findExif(with)).?);
    // APP0 stays first, EXIF right after it.
    try testing.expectEqualStrings("\xFF\xD8\xFF\xE0", with[0..4]);
    try testing.expectEqualStrings("\xFF\xE1", with[11..13]);

    const replaced = try replaceExif(testing.allocator, with, "NEW");
    defer testing.allocator.free(replaced);
    try testing.expectEqualStrings("NEW", (try findExif(replaced)).?);
    try testing.expectEqual(sample.len + 2 + 2 + 6 + 3, replaced.len);

    const removed = try replaceExif(testing.allocator, replaced, null);
    defer testing.allocator.free(removed);
    try testing.expectEqualStrings(sample, removed);
}

test "rejects non-jpeg and truncated data" {
    try testing.expectError(error.NotJpeg, findExif("not a jpeg"));
    try testing.expectError(error.Truncated, findExif("\xFF\xD8\xFF\xE1\x00\x20Exif"));
    const big = try testing.allocator.alloc(u8, 70000);
    defer testing.allocator.free(big);
    try testing.expectError(error.ExifTooLarge, replaceExif(testing.allocator, sample, big));
}
