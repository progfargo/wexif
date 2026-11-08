//! A calendar date and time as stored in EXIF ("YYYY:MM:DD HH:MM:SS"),
//! with an optional UTC offset (stored separately in the OffsetTime* tags).

const std = @import("std");
const epoch = std.time.epoch;

const DateTime = @This();

year: u16,
month: u8,
day: u8,
hour: u8 = 0,
minute: u8 = 0,
second: u8 = 0,
/// Offset from UTC in minutes, e.g. 180 for "+03:00". Null if unknown.
utc_offset: ?i16 = null,

pub const Error = error{InvalidDateTime};

/// Checks that every field is in range (including leap years).
pub fn validate(self: DateTime) Error!void {
    if (self.year < 1 or self.year > 9999) return error.InvalidDateTime;
    if (self.month < 1 or self.month > 12) return error.InvalidDateTime;
    const days = epoch.getDaysInMonth(self.year, @fromBackingInt(@intCast(self.month)));
    if (self.day < 1 or self.day > days) return error.InvalidDateTime;
    if (self.hour > 23 or self.minute > 59 or self.second > 59) return error.InvalidDateTime;
    if (self.utc_offset) |o| if (o < -14 * 60 or o > 14 * 60) return error.InvalidDateTime;
}

/// Parses "YYYY:MM:DD HH:MM:SS". Also accepts "-" in the date and "T"
/// between date and time ("2026-11-08T18:30:00"), and an optional trailing
/// offset ("+03:00", "-05:30" or "Z").
pub fn parse(text: []const u8) Error!DateTime {
    if (text.len < 19) return error.InvalidDateTime;
    const t = text;
    if (!(t[4] == ':' or t[4] == '-') or t[7] != t[4]) return error.InvalidDateTime;
    if (!(t[10] == ' ' or t[10] == 'T') or t[13] != ':' or t[16] != ':') return error.InvalidDateTime;
    var dt: DateTime = .{
        .year = try num(u16, t[0..4]),
        .month = try num(u8, t[5..7]),
        .day = try num(u8, t[8..10]),
        .hour = try num(u8, t[11..13]),
        .minute = try num(u8, t[14..16]),
        .second = try num(u8, t[17..19]),
    };
    const rest = std.mem.trim(u8, t[19..], " ");
    if (rest.len > 0) dt.utc_offset = try parseOffset(rest);
    try dt.validate();
    return dt;
}

/// Parses a UTC offset: "+03:00", "-05:30" or "Z". Returns minutes.
pub fn parseOffset(text: []const u8) Error!i16 {
    if (std.mem.eql(u8, text, "Z")) return 0;
    if (text.len != 6 or text[3] != ':') return error.InvalidDateTime;
    const sign: i16 = switch (text[0]) {
        '+' => 1,
        '-' => -1,
        else => return error.InvalidDateTime,
    };
    const h = try num(u8, text[1..3]);
    const m = try num(u8, text[4..6]);
    if (h > 14 or m > 59) return error.InvalidDateTime;
    return sign * (@as(i16, h) * 60 + m);
}

fn num(comptime T: type, digits: []const u8) Error!T {
    for (digits) |c| if (!std.ascii.isDigit(c)) return error.InvalidDateTime;
    return std.fmt.parseInt(T, digits, 10) catch error.InvalidDateTime;
}

/// The EXIF date/time text, "YYYY:MM:DD HH:MM:SS" (19 bytes).
pub fn exifString(self: DateTime) [19]u8 {
    var buf: [19]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d:0>4}:{d:0>2}:{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        self.year, self.month, self.day, self.hour, self.minute, self.second,
    }) catch unreachable;
    return buf;
}

/// The EXIF offset text, "+HH:MM" (6 bytes), or null if no offset is set.
pub fn offsetString(self: DateTime) ?[6]u8 {
    const o = self.utc_offset orelse return null;
    const abs: u16 = @abs(o);
    var buf: [6]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}", .{
        @as(u8, if (o < 0) '-' else '+'), abs / 60, abs % 60,
    }) catch unreachable;
    return buf;
}

/// Formats as "YYYY:MM:DD HH:MM:SS" plus " +HH:MM" when an offset is set. Use with `{f}`.
pub fn format(self: DateTime, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeAll(&self.exifString());
    if (self.offsetString()) |o| {
        try w.writeByte(' ');
        try w.writeAll(&o);
    }
}

const testing = std.testing;

test "parse and format" {
    const dt = try parse("2026:11:08 18:30:05");
    try testing.expectEqual(@as(u16, 2026), dt.year);
    try testing.expectEqual(@as(u8, 5), dt.second);
    try testing.expect(dt.utc_offset == null);
    try testing.expectEqualStrings("2026:11:08 18:30:05", &dt.exifString());

    const iso = try parse("2024-02-29T07:05:00-05:30");
    try testing.expectEqual(@as(i16, -330), iso.utc_offset.?);
    try testing.expectEqualStrings("-05:30", &iso.offsetString().?);
    try testing.expectEqual(@as(i16, 0), (try parse("2024-01-01T00:00:00Z")).utc_offset.?);

    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("2024:02:29 07:05:00 -05:30", try std.fmt.bufPrint(&buf, "{f}", .{iso}));
}

test "rejects invalid dates" {
    const bad = [_][]const u8{
        "2023:02:29 00:00:00", // not a leap year
        "2026:13:01 00:00:00",
        "2026:11:08 24:00:00",
        "2026:11:08 18:30",
        "    :  :     :  :  ", // "unknown" placeholder some cameras write
        "2026:11-08 18:30:00",
        "2026:11:08 18:30:00 +3",
        "2026:11:08 18:30:00 +15:00",
    };
    for (bad) |b| try testing.expectError(error.InvalidDateTime, parse(b));
    try testing.expectError(error.InvalidDateTime, (DateTime{ .year = 2026, .month = 4, .day = 31 }).validate());
}
