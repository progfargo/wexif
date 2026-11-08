//! Core EXIF data types.

const std = @import("std");

/// The image file directories (IFDs) an EXIF block can contain.
pub const IfdKind = enum(u3) {
    /// Main image (TIFF tags: Make, Model, Orientation, ...).
    ifd0,
    /// Exif sub-IFD (exposure, dates, lens, ...).
    exif,
    /// GPS sub-IFD.
    gps,
    /// Interoperability sub-IFD.
    interop,
    /// Thumbnail image IFD.
    ifd1,

    pub const count = std.meta.tags(IfdKind).len;
};

/// TIFF field types.
pub const Type = enum(u16) {
    byte = 1,
    ascii = 2,
    short = 3,
    long = 4,
    rational = 5,
    sbyte = 6,
    undefined = 7,
    sshort = 8,
    slong = 9,
    srational = 10,
    float = 11,
    double = 12,
    _,

    /// Size in bytes of one component, or null for unknown types.
    pub fn size(self: Type) ?u32 {
        return switch (self) {
            .byte, .ascii, .sbyte, .undefined => 1,
            .short, .sshort => 2,
            .long, .slong, .float => 4,
            .rational, .srational, .double => 8,
            _ => null,
        };
    }
};

pub const Rational = struct {
    num: u32,
    den: u32,

    pub fn toFloat(self: Rational) f64 {
        if (self.den == 0) return 0;
        return @as(f64, @floatFromInt(self.num)) / @as(f64, @floatFromInt(self.den));
    }
};

pub const SRational = struct {
    num: i32,
    den: i32,

    pub fn toFloat(self: SRational) f64 {
        if (self.den == 0) return 0;
        return @as(f64, @floatFromInt(self.num)) / @as(f64, @floatFromInt(self.den));
    }
};

/// A decoded tag value. ASCII values keep their trailing NUL, as stored in the file.
pub const Value = union(enum) {
    byte: []const u8,
    ascii: []const u8,
    short: []const u16,
    long: []const u32,
    rational: []const Rational,
    sbyte: []const i8,
    undefined: []const u8,
    sshort: []const i16,
    slong: []const i32,
    srational: []const SRational,
    float: []const f32,
    double: []const f64,

    pub fn typ(self: Value) Type {
        return switch (self) {
            inline else => |_, tag| @field(Type, @tagName(tag)),
        };
    }

    /// Number of components.
    pub fn count(self: Value) u32 {
        return switch (self) {
            inline else => |s| @intCast(s.len),
        };
    }

    /// Encoded size in bytes.
    pub fn byteSize(self: Value) u32 {
        return self.count() * self.typ().size().?;
    }

    /// ASCII text without trailing NULs (only for `.ascii`).
    pub fn string(self: Value) ?[]const u8 {
        return switch (self) {
            .ascii => |s| std.mem.trimEnd(u8, s, "\x00"),
            else => null,
        };
    }

    /// First component as an unsigned integer (byte/short/long only).
    pub fn uint(self: Value) ?u32 {
        return switch (self) {
            .byte => |s| if (s.len > 0) s[0] else null,
            .short => |s| if (s.len > 0) s[0] else null,
            .long => |s| if (s.len > 0) s[0] else null,
            else => null,
        };
    }

    /// Returns a deep copy allocated with `gpa`.
    pub fn dupe(self: Value, gpa: std.mem.Allocator) !Value {
        return switch (self) {
            inline else => |s, tag| @unionInit(Value, @tagName(tag), try gpa.dupe(@TypeOf(s[0]), s)),
        };
    }

    /// Human-readable representation. Use with `{f}`.
    pub fn format(self: Value, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .ascii => |s| try w.print("\"{s}\"", .{std.mem.trimEnd(u8, s, "\x00")}),
            .undefined, .byte => |s| {
                if (s.len > 32) return w.print("({d} bytes)", .{s.len});
                if (isPrintable(s)) return w.print("\"{s}\"", .{s});
                for (s, 0..) |b, i| {
                    if (i > 0) try w.writeByte(' ');
                    try w.print("{x:0>2}", .{b});
                }
            },
            .rational => |s| for (s, 0..) |r, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("{d}/{d}", .{ r.num, r.den });
            },
            .srational => |s| for (s, 0..) |r, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("{d}/{d}", .{ r.num, r.den });
            },
            inline else => |s| {
                if (s.len > 16) return w.print("({d} values)", .{s.len});
                for (s, 0..) |v, i| {
                    if (i > 0) try w.writeAll(", ");
                    try w.print("{d}", .{v});
                }
            },
        }
    }
};

fn isPrintable(s: []const u8) bool {
    const trimmed = std.mem.trimEnd(u8, s, "\x00");
    if (trimmed.len == 0) return false;
    for (trimmed) |c| if (!std.ascii.isPrint(c)) return false;
    return true;
}

/// A single tag in an IFD.
pub const Entry = struct {
    tag: u16,
    value: Value,
};
