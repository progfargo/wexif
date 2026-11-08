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
zig fetch --save git+https://github.com/progfargo/wexif#v0.1.0
```

`build.zig`:

```zig
const wexif = b.dependency("wexif", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("wexif", wexif.module("wexif"));
```

## Library usage

Tags are referred to by name. Each name already knows which IFD it belongs to,
so `.orientation` means IFD0's Orientation and `.exposure_time` means the Exif
IFD's ExposureTime. All names are listed in [`src/tags.zig`](src/tags.zig).

### Example: update orientation, date, description and comment

```zig
const std = @import("std");
const wexif = @import("wexif");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Read (create an empty block if the image has no EXIF)
    var exif = (try wexif.readFile(gpa, io, "photo.jpg")) orelse wexif.Exif.init(gpa, .little);
    defer exif.deinit();

    try exif.setOrientation(.normal);
    try exif.setDateTime(.{ .year = 2026, .month = 11, .day = 8, .hour = 18, .minute = 30, .utc_offset = 3 * 60 });
    try exif.setDescription("Sunset over the Bosphorus");
    try exif.setUserComment("Shot on a phone, unedited");

    try wexif.writeFile(gpa, io, "photo.jpg", "photo_new.jpg", &exif);
}
```

### Common fields

These helpers cover the fields people edit most and handle their encoding details.

```zig
// Orientation: a display flag, it does not rotate pixels.
// After rotating the pixels yourself, set it back to .normal.
if (exif.getOrientation()) |o| std.debug.print("orientation: {t}\n", .{o}); // e.g. rotate_90_cw
try exif.setOrientation(.rotate_90_cw);

// Date taken: sets DateTimeOriginal, DateTimeDigitized and DateTime,
// plus the OffsetTime* tags when utc_offset (minutes) is given.
try exif.setDateTime(try wexif.DateTime.parse("2026-11-08T18:30:00+03:00"));
if (exif.getDateTime()) |dt| std.debug.print("taken: {f}\n", .{dt}); // 2026:11:08 18:30:00 +03:00

// ImageDescription
try exif.setDescription("Sunset over the Bosphorus");
if (exif.getDescription()) |d| std.debug.print("description: {s}\n", .{d});

// UserComment: plain ASCII is stored as ASCII, anything else as UTF-16 ("UNICODE").
try exif.setUserComment("Café \u{1F4F7}");
if (try exif.getUserComment(gpa)) |c| {
    defer gpa.free(c);
    std.debug.print("comment: {s}\n", .{c});
}
```

`DateTime.parse` accepts `"2026:11:08 18:30:00"`, `"2026-11-08 18:30:00"` and
`"2026-11-08T18:30:00"`, each with an optional `+HH:MM`, `-HH:MM` or `Z`.
Invalid dates (e.g. February 30) return `error.InvalidDateTime`.

### Reading

```zig
const make = exif.getString(.make);              // ?[]const u8
const orientation = exif.getUint(.orientation);  // ?u32
const exposure = exif.get(.exposure_time);       // ?Value, e.g. .rational
const location = exif.getGps();                  // ?{ latitude, longitude, altitude }

// Iterate all entries of an IFD
for (exif.entries(.exif)) |e| {
    const name = wexif.tags.name(.{ .kind = .exif, .num = e.tag }) orelse "?";
    std.debug.print("{s} = {f}\n", .{ name, e.value });
}
```

### Editing

```zig
try exif.setString(.artist, "Jane Doe");
try exif.setString(.copyright, "(c) 2026 Jane Doe");
try exif.setRational(.exposure_time, 1, 250);
try exif.setRational(.f_number, 28, 10);
try exif.setShort(.iso_speed_ratings, 400);
try exif.set(.exposure_bias_value, .{ .srational = &.{.{ .num = -1, .den = 3 }} });
try exif.setGps(.{ .latitude = 41.0082, .longitude = 28.9784, .altitude = 35 });

// Thumbnail IFD: same names, moved with `in`
try exif.setShort(wexif.Tag.orientation.in(.ifd1), 1);

// Tags without a name: give the IFD and number directly
try exif.setString(.{ .kind = .exif, .num = 0xA431 }, "SN12345");

// Look up a tag from a string (e.g. user input)
const info = wexif.tags.find("LensModel").?;     // .tag, .name, .type
_ = exif.remove(info.tag);
```

### Removing

```zig
_ = exif.remove(.lens_model);   // one tag; returns true if it existed
exif.clear(.gps);               // a whole IFD, e.g. all location data
exif.removeThumbnail();
exif.clearAll();                // everything; writing it removes the EXIF segment
```

### JSON

`exifToJson` returns every tag as JSON, keyed by name:

```zig
var exif = (try wexif.readFile(gpa, io, "photo.jpg")) orelse return;
defer exif.deinit();

const json = try wexif.exifToJson(gpa, &exif);
defer gpa.free(json);
std.debug.print("{s}\n", .{json});
```

```json
{
  "byteOrder": "big",
  "ifd0": {
    "ImageDescription": "Sunset",
    "Make": "Canon",
    "Model": "EOS R5",
    "Orientation": 6,
    "XPTitle": "Café title"
  },
  "exif": {
    "ExposureTime": 0.004,
    "FNumber": 2.8,
    "ISOSpeedRatings": 400,
    "DateTimeOriginal": "2024:05:01 10:20:30",
    "ComponentsConfiguration": "01020300",
    "ExposureBiasValue": -0.7,
    "UserComment": "Shot on a phone"
  },
  "gps": {
    "GPSLatitudeRef": "N",
    "GPSLatitude": [41, 0, 29.52],
    "GPSLongitudeRef": "E",
    "GPSLongitude": [28, 58, 42.24]
  },
  "location": { "latitude": 41.0082, "longitude": 28.9784, "altitude": 35 },
  "thumbnailSize": 909
}
```

- Text becomes a string; UserComment and the Windows `XP*` tags are decoded.
- One number becomes a number, several become an array; rationals become decimals.
- Other binary data becomes a hex string, or `"(N bytes)"` above 256 bytes (e.g. MakerNote).
- Unknown tags are keyed as `"0xNNNN"`; empty IFDs are omitted.

For compact output, other limits, or writing straight to a file or socket, use
`wexif.json.write(&exif, writer, .{ .whitespace = .minified, .max_binary_len = 64 })`.

### Writing

```zig
// In memory (pass null instead of &exif to strip all EXIF)
const out = try wexif.writeJpeg(gpa, jpeg_bytes, &exif);
defer gpa.free(out);

// File to file (in and out may be the same path)
try wexif.writeFile(gpa, io, "photo.jpg", "photo_new.jpg", &exif);
```

All memory is owned by `Exif`; `set*` copies its input, and `deinit` frees everything.

## CLI

```sh
zig build
./zig-out/bin/wexif show photo.jpg
./zig-out/bin/wexif json photo.jpg                   # all EXIF as JSON
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

Built with [Claude Code](https://claude.com/claude-code). I defined the
features and the API requirements, reviewed the results and tested the
library; Claude wrote most of the code.

## License

MIT
