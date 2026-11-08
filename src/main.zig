//! wexif command-line tool.

const std = @import("std");
const Io = std.Io;
const wexif = @import("wexif");
const Exif = wexif.Exif;
const IfdKind = wexif.IfdKind;

const usage =
    \\Usage:
    \\  wexif show  <in.jpg>
    \\  wexif set   <in.jpg> <out.jpg> TAG=VALUE...
    \\  wexif rm    <in.jpg> <out.jpg> TAG...
    \\  wexif gps   <in.jpg> <out.jpg> <lat> <lon> [altitude_m]
    \\  wexif strip <in.jpg> <out.jpg> [all|gps|thumbnail]
    \\
    \\TAG is a known name (Artist, DateTimeOriginal, GPSLatitude, ...),
    \\optionally prefixed with an IFD (ifd0., exif., gps., interop., ifd1.),
    \\or a raw tag as IFD.0xNNNN:TYPE (e.g. exif.0xA431:ascii).
    \\in and out may be the same file.
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var buf: [4096]u8 = undefined;
    var fw: Io.File.Writer = .init(.stdout(), io, &buf);
    const out = &fw.interface;
    defer out.flush() catch {};

    if (args.len < 3) fatal("{s}", .{usage});
    const cmd = args[1];
    const in_path = args[2];

    if (std.mem.eql(u8, cmd, "show")) {
        var ex = (readOrFail(arena, io, in_path)) orelse {
            try out.writeAll("no EXIF data\n");
            return;
        };
        defer ex.deinit();
        try show(out, &ex);
        return;
    }

    if (args.len < 4) fatal("{s}", .{usage});
    const out_path = args[3];
    const rest = args[4..];

    var ex = readOrFail(arena, io, in_path) orelse Exif.init(arena, .little);
    defer ex.deinit();

    if (std.mem.eql(u8, cmd, "set")) {
        if (rest.len == 0) fatal("set: no TAG=VALUE given", .{});
        for (rest) |arg| {
            const eq = std.mem.indexOfScalar(u8, arg, '=') orelse fatal("set: expected TAG=VALUE, got '{s}'", .{arg});
            const spec = parseTag(arg[0..eq]);
            const value = wexif.parseValue(arena, spec.type, arg[eq + 1 ..]) catch
                fatal("set: invalid {t} value '{s}'", .{ spec.type, arg[eq + 1 ..] });
            ex.set(spec.tag, value) catch |err| fatal("set {s}: {t}", .{ arg[0..eq], err });
        }
    } else if (std.mem.eql(u8, cmd, "rm")) {
        for (rest) |arg| {
            const spec = parseTag(arg);
            if (!ex.remove(spec.tag)) std.debug.print("warning: {s} not present\n", .{arg});
        }
    } else if (std.mem.eql(u8, cmd, "gps")) {
        if (rest.len < 2) fatal("gps: need <lat> <lon>", .{});
        const lat = std.fmt.parseFloat(f64, rest[0]) catch fatal("gps: bad latitude", .{});
        const lon = std.fmt.parseFloat(f64, rest[1]) catch fatal("gps: bad longitude", .{});
        const alt = if (rest.len > 2) std.fmt.parseFloat(f64, rest[2]) catch fatal("gps: bad altitude", .{}) else null;
        ex.setGps(.{ .latitude = lat, .longitude = lon, .altitude = alt }) catch fatal("gps: coordinates out of range", .{});
    } else if (std.mem.eql(u8, cmd, "strip")) {
        const what = if (rest.len > 0) rest[0] else "all";
        if (std.mem.eql(u8, what, "all")) {
            return writeOrFail(arena, io, in_path, out_path, null);
        } else if (std.mem.eql(u8, what, "gps")) {
            ex.clear(.gps);
        } else if (std.mem.eql(u8, what, "thumbnail")) {
            ex.removeThumbnail();
        } else fatal("strip: unknown target '{s}'", .{what});
    } else fatal("unknown command '{s}'\n\n{s}", .{ cmd, usage });

    writeOrFail(arena, io, in_path, out_path, &ex);
}

fn readOrFail(gpa: std.mem.Allocator, io: Io, path: []const u8) ?Exif {
    return wexif.readFile(gpa, io, path) catch |err| fatal("{s}: {t}", .{ path, err });
}

fn writeOrFail(gpa: std.mem.Allocator, io: Io, in_path: []const u8, out_path: []const u8, ex: ?*const Exif) void {
    wexif.writeFile(gpa, io, in_path, out_path, ex) catch |err| fatal("{s}: {t}", .{ out_path, err });
}

const TagSpec = struct { tag: wexif.Tag, type: wexif.Type };

/// Parses `[ifd.]Name` or `ifd.0xNNNN:type`.
fn parseTag(text: []const u8) TagSpec {
    var kind: ?IfdKind = null;
    var name = text;
    if (std.mem.indexOfScalar(u8, text, '.')) |dot| {
        kind = std.meta.stringToEnum(IfdKind, text[0..dot]) orelse fatal("unknown IFD '{s}'", .{text[0..dot]});
        name = text[dot + 1 ..];
    }
    if (std.mem.startsWith(u8, name, "0x")) {
        const colon = std.mem.indexOfScalar(u8, name, ':') orelse fatal("raw tag needs a type: {s}:ascii", .{text});
        const tag = std.fmt.parseInt(u16, name[0..colon], 0) catch fatal("bad tag number '{s}'", .{name[0..colon]});
        const ty = std.meta.stringToEnum(wexif.Type, name[colon + 1 ..]) orelse fatal("unknown type '{s}'", .{name[colon + 1 ..]});
        return .{ .tag = .{ .kind = kind orelse .ifd0, .num = tag }, .type = ty };
    }
    const info = wexif.tags.find(name) orelse fatal("unknown tag '{s}' (use IFD.0xNNNN:TYPE for raw tags)", .{name});
    return .{ .tag = info.tag.in(kind orelse info.tag.kind), .type = info.type };
}

fn show(w: *Io.Writer, ex: *const Exif) !void {
    try w.print("byte order: {t}\n", .{ex.byte_order});
    for (std.meta.tags(IfdKind)) |kind| {
        const list = ex.entries(kind);
        if (list.len > 0) {
            try w.print("\n[{t}]\n", .{kind});
            for (list) |e| {
                const name = wexif.tags.name(.{ .kind = kind, .num = e.tag }) orelse "?";
                try w.print("  0x{x:0>4} {s:<26} {t:<9} {f}\n", .{ e.tag, name, e.value.typ(), e.value });
            }
        }
    }
    if (ex.getGps()) |g| {
        try w.print("\nlocation: {d:.6}, {d:.6}", .{ g.latitude, g.longitude });
        if (g.altitude) |a| try w.print(" ({d:.1} m)", .{a});
        try w.writeByte('\n');
    }
    if (ex.thumbnail) |th| try w.print("thumbnail: {d} bytes\n", .{th.len});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("wexif: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}
