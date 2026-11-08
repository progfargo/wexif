# wexif

A small, dependency-free Zig library (and CLI) for reading and editing EXIF metadata in JPEG files.

- Reads IFD0, Exif, GPS, Interoperability and IFD1 (thumbnail) directories
- Both byte orders (`II` / `MM`), all 12 TIFF value types
- Add, change and remove any tag; helpers for strings, numbers, rationals and GPS coordinates
- Rebuilds the EXIF block with correct offsets; image data is copied byte for byte
- Bounds-checked parser: truncated or malicious input returns an error, never crashes
- Requires Zig 0.17

## Install

```sh
zig fetch --save git+https://github.com/progfargo/wexif
```

`build.zig`:

```zig
const wexif = b.dependency("wexif", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("wexif", wexif.module("wexif"));
```

## Library usage

```zig
const wexif = @import("wexif");

// Parse from memory (returns null if the JPEG has no EXIF)
var exif = (try wexif.readJpeg(gpa, jpeg_bytes)) orelse wexif.Exif.init(gpa, .little);
defer exif.deinit();

// Read
if (exif.getString(.ifd0, 0x010F)) |make| std.debug.print("Make: {s}\n", .{make});
if (exif.getUint(.ifd0, 0x0112)) |orientation| _ = orientation;
if (exif.getGps()) |g| std.debug.print("{d}, {d}\n", .{ g.latitude, g.longitude });

// Iterate everything
for (exif.entries(.exif)) |e| {
    std.debug.print("{s} = {f}\n", .{ wexif.tags.name(.exif, e.tag) orelse "?", e.value });
}

// Edit
try exif.setString(.ifd0, wexif.tags.find("Artist").?.tag, "Jane Doe");
try exif.setRational(.exif, 0x829A, 1, 250); // ExposureTime
try exif.set(.exif, 0x9204, .{ .srational = &.{.{ .num = -1, .den = 3 }} });
try exif.setGps(.{ .latitude = 41.0082, .longitude = 28.9784, .altitude = 35 });
_ = exif.remove(.exif, 0xA434); // LensModel
exif.clear(.gps);               // drop all location data
exif.removeThumbnail();

// Write back (pass null instead of &exif to strip all EXIF)
const out = try wexif.writeJpeg(gpa, jpeg_bytes, &exif);
defer gpa.free(out);
```

File helpers: `wexif.readFile(gpa, io, path)` and `wexif.writeFile(gpa, io, in_path, out_path, &exif)`.

## CLI

```sh
zig build
./zig-out/bin/wexif show photo.jpg
./zig-out/bin/wexif set photo.jpg out.jpg Artist="Jane" ExposureTime=1/250 FNumber=2.8
./zig-out/bin/wexif set photo.jpg out.jpg ifd1.Orientation=1 exif.0xA431:ascii=SN123
./zig-out/bin/wexif rm photo.jpg out.jpg LensModel
./zig-out/bin/wexif gps photo.jpg out.jpg 41.0082 28.9784 35
./zig-out/bin/wexif strip photo.jpg out.jpg          # all | gps | thumbnail
```

## Limitations

- **MakerNote**: kept as opaque bytes. Many vendors store absolute offsets inside it,
  so after rewriting the block those internal offsets may no longer be valid.
  Standard tags are not affected.
- Only JPEG thumbnails in IFD1 are preserved; strip-based (uncompressed) thumbnails are dropped.
- The EXIF block must fit in one APP1 segment (~64 KB), as required by the JPEG format.
- XMP, IPTC and ICC data are left untouched (copied as-is).

## Tests

```sh
zig build test
```

Written with Claude.

## License

MIT
