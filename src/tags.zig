//! Known EXIF/TIFF tag table: names, owning IFD and default value type.

const std = @import("std");
const types = @import("types.zig");
const IfdKind = types.IfdKind;
const Type = types.Type;

pub const TagInfo = struct {
    kind: IfdKind,
    tag: u16,
    name: []const u8,
    type: Type,
};

fn t(kind: IfdKind, tag: u16, tag_name: []const u8, ty: Type) TagInfo {
    return .{ .kind = kind, .tag = tag, .name = tag_name, .type = ty };
}

/// Pointer tags. They are managed by the library and never appear as entries.
pub const exif_ifd_pointer: u16 = 0x8769;
pub const gps_ifd_pointer: u16 = 0x8825;
pub const interop_ifd_pointer: u16 = 0xA005;
pub const thumbnail_offset: u16 = 0x0201;
pub const thumbnail_length: u16 = 0x0202;

pub const table = [_]TagInfo{
    // IFD0 (TIFF) tags. Also valid in IFD1.
    t(.ifd0, 0x0100, "ImageWidth", .long),
    t(.ifd0, 0x0101, "ImageLength", .long),
    t(.ifd0, 0x0102, "BitsPerSample", .short),
    t(.ifd0, 0x0103, "Compression", .short),
    t(.ifd0, 0x0106, "PhotometricInterpretation", .short),
    t(.ifd0, 0x010E, "ImageDescription", .ascii),
    t(.ifd0, 0x010F, "Make", .ascii),
    t(.ifd0, 0x0110, "Model", .ascii),
    t(.ifd0, 0x0112, "Orientation", .short),
    t(.ifd0, 0x0115, "SamplesPerPixel", .short),
    t(.ifd0, 0x011A, "XResolution", .rational),
    t(.ifd0, 0x011B, "YResolution", .rational),
    t(.ifd0, 0x011C, "PlanarConfiguration", .short),
    t(.ifd0, 0x0128, "ResolutionUnit", .short),
    t(.ifd0, 0x012D, "TransferFunction", .short),
    t(.ifd0, 0x0131, "Software", .ascii),
    t(.ifd0, 0x0132, "DateTime", .ascii),
    t(.ifd0, 0x013B, "Artist", .ascii),
    t(.ifd0, 0x013E, "WhitePoint", .rational),
    t(.ifd0, 0x013F, "PrimaryChromaticities", .rational),
    t(.ifd0, 0x0211, "YCbCrCoefficients", .rational),
    t(.ifd0, 0x0212, "YCbCrSubSampling", .short),
    t(.ifd0, 0x0213, "YCbCrPositioning", .short),
    t(.ifd0, 0x0214, "ReferenceBlackWhite", .rational),
    t(.ifd0, 0x4746, "Rating", .short),
    t(.ifd0, 0x8298, "Copyright", .ascii),
    t(.ifd0, 0x9C9B, "XPTitle", .byte),
    t(.ifd0, 0x9C9C, "XPComment", .byte),
    t(.ifd0, 0x9C9D, "XPAuthor", .byte),
    t(.ifd0, 0x9C9E, "XPKeywords", .byte),
    t(.ifd0, 0x9C9F, "XPSubject", .byte),

    // Exif IFD
    t(.exif, 0x829A, "ExposureTime", .rational),
    t(.exif, 0x829D, "FNumber", .rational),
    t(.exif, 0x8822, "ExposureProgram", .short),
    t(.exif, 0x8824, "SpectralSensitivity", .ascii),
    t(.exif, 0x8827, "ISOSpeedRatings", .short),
    t(.exif, 0x8828, "OECF", .undefined),
    t(.exif, 0x8830, "SensitivityType", .short),
    t(.exif, 0x9000, "ExifVersion", .undefined),
    t(.exif, 0x9003, "DateTimeOriginal", .ascii),
    t(.exif, 0x9004, "DateTimeDigitized", .ascii),
    t(.exif, 0x9010, "OffsetTime", .ascii),
    t(.exif, 0x9011, "OffsetTimeOriginal", .ascii),
    t(.exif, 0x9012, "OffsetTimeDigitized", .ascii),
    t(.exif, 0x9101, "ComponentsConfiguration", .undefined),
    t(.exif, 0x9102, "CompressedBitsPerPixel", .rational),
    t(.exif, 0x9201, "ShutterSpeedValue", .srational),
    t(.exif, 0x9202, "ApertureValue", .rational),
    t(.exif, 0x9203, "BrightnessValue", .srational),
    t(.exif, 0x9204, "ExposureBiasValue", .srational),
    t(.exif, 0x9205, "MaxApertureValue", .rational),
    t(.exif, 0x9206, "SubjectDistance", .rational),
    t(.exif, 0x9207, "MeteringMode", .short),
    t(.exif, 0x9208, "LightSource", .short),
    t(.exif, 0x9209, "Flash", .short),
    t(.exif, 0x920A, "FocalLength", .rational),
    t(.exif, 0x9214, "SubjectArea", .short),
    t(.exif, 0x927C, "MakerNote", .undefined),
    t(.exif, 0x9286, "UserComment", .undefined),
    t(.exif, 0x9290, "SubSecTime", .ascii),
    t(.exif, 0x9291, "SubSecTimeOriginal", .ascii),
    t(.exif, 0x9292, "SubSecTimeDigitized", .ascii),
    t(.exif, 0xA000, "FlashpixVersion", .undefined),
    t(.exif, 0xA001, "ColorSpace", .short),
    t(.exif, 0xA002, "PixelXDimension", .long),
    t(.exif, 0xA003, "PixelYDimension", .long),
    t(.exif, 0xA004, "RelatedSoundFile", .ascii),
    t(.exif, 0xA20B, "FlashEnergy", .rational),
    t(.exif, 0xA20E, "FocalPlaneXResolution", .rational),
    t(.exif, 0xA20F, "FocalPlaneYResolution", .rational),
    t(.exif, 0xA210, "FocalPlaneResolutionUnit", .short),
    t(.exif, 0xA214, "SubjectLocation", .short),
    t(.exif, 0xA215, "ExposureIndex", .rational),
    t(.exif, 0xA217, "SensingMethod", .short),
    t(.exif, 0xA300, "FileSource", .undefined),
    t(.exif, 0xA301, "SceneType", .undefined),
    t(.exif, 0xA302, "CFAPattern", .undefined),
    t(.exif, 0xA401, "CustomRendered", .short),
    t(.exif, 0xA402, "ExposureMode", .short),
    t(.exif, 0xA403, "WhiteBalance", .short),
    t(.exif, 0xA404, "DigitalZoomRatio", .rational),
    t(.exif, 0xA405, "FocalLengthIn35mmFilm", .short),
    t(.exif, 0xA406, "SceneCaptureType", .short),
    t(.exif, 0xA407, "GainControl", .short),
    t(.exif, 0xA408, "Contrast", .short),
    t(.exif, 0xA409, "Saturation", .short),
    t(.exif, 0xA40A, "Sharpness", .short),
    t(.exif, 0xA40C, "SubjectDistanceRange", .short),
    t(.exif, 0xA420, "ImageUniqueID", .ascii),
    t(.exif, 0xA430, "CameraOwnerName", .ascii),
    t(.exif, 0xA431, "BodySerialNumber", .ascii),
    t(.exif, 0xA432, "LensSpecification", .rational),
    t(.exif, 0xA433, "LensMake", .ascii),
    t(.exif, 0xA434, "LensModel", .ascii),
    t(.exif, 0xA435, "LensSerialNumber", .ascii),
    t(.exif, 0xA500, "Gamma", .rational),

    // GPS IFD
    t(.gps, 0x0000, "GPSVersionID", .byte),
    t(.gps, 0x0001, "GPSLatitudeRef", .ascii),
    t(.gps, 0x0002, "GPSLatitude", .rational),
    t(.gps, 0x0003, "GPSLongitudeRef", .ascii),
    t(.gps, 0x0004, "GPSLongitude", .rational),
    t(.gps, 0x0005, "GPSAltitudeRef", .byte),
    t(.gps, 0x0006, "GPSAltitude", .rational),
    t(.gps, 0x0007, "GPSTimeStamp", .rational),
    t(.gps, 0x0008, "GPSSatellites", .ascii),
    t(.gps, 0x0009, "GPSStatus", .ascii),
    t(.gps, 0x000A, "GPSMeasureMode", .ascii),
    t(.gps, 0x000B, "GPSDOP", .rational),
    t(.gps, 0x000C, "GPSSpeedRef", .ascii),
    t(.gps, 0x000D, "GPSSpeed", .rational),
    t(.gps, 0x000E, "GPSTrackRef", .ascii),
    t(.gps, 0x000F, "GPSTrack", .rational),
    t(.gps, 0x0010, "GPSImgDirectionRef", .ascii),
    t(.gps, 0x0011, "GPSImgDirection", .rational),
    t(.gps, 0x0012, "GPSMapDatum", .ascii),
    t(.gps, 0x0013, "GPSDestLatitudeRef", .ascii),
    t(.gps, 0x0014, "GPSDestLatitude", .rational),
    t(.gps, 0x0015, "GPSDestLongitudeRef", .ascii),
    t(.gps, 0x0016, "GPSDestLongitude", .rational),
    t(.gps, 0x0017, "GPSDestBearingRef", .ascii),
    t(.gps, 0x0018, "GPSDestBearing", .rational),
    t(.gps, 0x0019, "GPSDestDistanceRef", .ascii),
    t(.gps, 0x001A, "GPSDestDistance", .rational),
    t(.gps, 0x001B, "GPSProcessingMethod", .undefined),
    t(.gps, 0x001C, "GPSAreaInformation", .undefined),
    t(.gps, 0x001D, "GPSDateStamp", .ascii),
    t(.gps, 0x001E, "GPSDifferential", .short),
    t(.gps, 0x001F, "GPSHPositioningError", .rational),

    // Interoperability IFD
    t(.interop, 0x0001, "InteroperabilityIndex", .ascii),
    t(.interop, 0x0002, "InteroperabilityVersion", .undefined),
};

/// Finds a tag by its name (case-insensitive).
/// IFD0 tags are also valid in IFD1; the returned `kind` is the default IFD.
pub fn find(needle: []const u8) ?TagInfo {
    for (table) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, needle)) return entry;
    }
    return null;
}

/// Looks up a tag's info by its IFD and number.
pub fn info(kind: IfdKind, tag: u16) ?TagInfo {
    const k: IfdKind = if (kind == .ifd1) .ifd0 else kind;
    for (table) |i| {
        if (i.kind == k and i.tag == tag) return i;
    }
    return null;
}

/// Returns the tag's name, or null if unknown.
pub fn name(kind: IfdKind, tag: u16) ?[]const u8 {
    return if (info(kind, tag)) |i| i.name else null;
}

test "find and name" {
    const make = find("make").?;
    try std.testing.expectEqual(@as(u16, 0x010F), make.tag);
    try std.testing.expectEqual(IfdKind.ifd0, make.kind);
    try std.testing.expectEqualStrings("GPSLatitude", name(.gps, 2).?);
    try std.testing.expectEqualStrings("Orientation", name(.ifd1, 0x0112).?);
    try std.testing.expect(find("NoSuchTag") == null);
}
