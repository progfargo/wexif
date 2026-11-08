//! Known EXIF/TIFF tags: named constants, names and default value types.

const std = @import("std");
const types = @import("types.zig");
const IfdKind = types.IfdKind;
const Type = types.Type;

/// Identifies a tag: the IFD it lives in and its number.
///
/// Use the named constants, usually as decl literals:
/// `exif.setShort(.orientation, 1)`. For tags not listed here, build one
/// directly: `.{ .kind = .exif, .num = 0xA431 }`.
pub const Tag = struct {
    kind: IfdKind,
    num: u16,

    /// The same tag in another IFD, e.g. `Tag.orientation.in(.ifd1)`
    /// for the thumbnail's orientation.
    pub fn in(self: Tag, kind: IfdKind) Tag {
        return .{ .kind = kind, .num = self.num };
    }

    pub fn eql(a: Tag, b: Tag) bool {
        return a.kind == b.kind and a.num == b.num;
    }

    // IFD0 (TIFF) tags. Also valid in IFD1, see `in`.
    pub const image_width: Tag = .{ .kind = .ifd0, .num = 0x0100 };
    pub const image_length: Tag = .{ .kind = .ifd0, .num = 0x0101 };
    pub const bits_per_sample: Tag = .{ .kind = .ifd0, .num = 0x0102 };
    pub const compression: Tag = .{ .kind = .ifd0, .num = 0x0103 };
    pub const photometric_interpretation: Tag = .{ .kind = .ifd0, .num = 0x0106 };
    pub const image_description: Tag = .{ .kind = .ifd0, .num = 0x010E };
    pub const make: Tag = .{ .kind = .ifd0, .num = 0x010F };
    pub const model: Tag = .{ .kind = .ifd0, .num = 0x0110 };
    pub const orientation: Tag = .{ .kind = .ifd0, .num = 0x0112 };
    pub const samples_per_pixel: Tag = .{ .kind = .ifd0, .num = 0x0115 };
    pub const x_resolution: Tag = .{ .kind = .ifd0, .num = 0x011A };
    pub const y_resolution: Tag = .{ .kind = .ifd0, .num = 0x011B };
    pub const planar_configuration: Tag = .{ .kind = .ifd0, .num = 0x011C };
    pub const resolution_unit: Tag = .{ .kind = .ifd0, .num = 0x0128 };
    pub const transfer_function: Tag = .{ .kind = .ifd0, .num = 0x012D };
    pub const software: Tag = .{ .kind = .ifd0, .num = 0x0131 };
    pub const date_time: Tag = .{ .kind = .ifd0, .num = 0x0132 };
    pub const artist: Tag = .{ .kind = .ifd0, .num = 0x013B };
    pub const white_point: Tag = .{ .kind = .ifd0, .num = 0x013E };
    pub const primary_chromaticities: Tag = .{ .kind = .ifd0, .num = 0x013F };
    pub const ycbcr_coefficients: Tag = .{ .kind = .ifd0, .num = 0x0211 };
    pub const ycbcr_sub_sampling: Tag = .{ .kind = .ifd0, .num = 0x0212 };
    pub const ycbcr_positioning: Tag = .{ .kind = .ifd0, .num = 0x0213 };
    pub const reference_black_white: Tag = .{ .kind = .ifd0, .num = 0x0214 };
    pub const rating: Tag = .{ .kind = .ifd0, .num = 0x4746 };
    pub const copyright: Tag = .{ .kind = .ifd0, .num = 0x8298 };
    pub const xp_title: Tag = .{ .kind = .ifd0, .num = 0x9C9B };
    pub const xp_comment: Tag = .{ .kind = .ifd0, .num = 0x9C9C };
    pub const xp_author: Tag = .{ .kind = .ifd0, .num = 0x9C9D };
    pub const xp_keywords: Tag = .{ .kind = .ifd0, .num = 0x9C9E };
    pub const xp_subject: Tag = .{ .kind = .ifd0, .num = 0x9C9F };

    // Exif IFD
    pub const exposure_time: Tag = .{ .kind = .exif, .num = 0x829A };
    pub const f_number: Tag = .{ .kind = .exif, .num = 0x829D };
    pub const exposure_program: Tag = .{ .kind = .exif, .num = 0x8822 };
    pub const spectral_sensitivity: Tag = .{ .kind = .exif, .num = 0x8824 };
    pub const iso_speed_ratings: Tag = .{ .kind = .exif, .num = 0x8827 };
    pub const oecf: Tag = .{ .kind = .exif, .num = 0x8828 };
    pub const sensitivity_type: Tag = .{ .kind = .exif, .num = 0x8830 };
    pub const exif_version: Tag = .{ .kind = .exif, .num = 0x9000 };
    pub const date_time_original: Tag = .{ .kind = .exif, .num = 0x9003 };
    pub const date_time_digitized: Tag = .{ .kind = .exif, .num = 0x9004 };
    pub const offset_time: Tag = .{ .kind = .exif, .num = 0x9010 };
    pub const offset_time_original: Tag = .{ .kind = .exif, .num = 0x9011 };
    pub const offset_time_digitized: Tag = .{ .kind = .exif, .num = 0x9012 };
    pub const components_configuration: Tag = .{ .kind = .exif, .num = 0x9101 };
    pub const compressed_bits_per_pixel: Tag = .{ .kind = .exif, .num = 0x9102 };
    pub const shutter_speed_value: Tag = .{ .kind = .exif, .num = 0x9201 };
    pub const aperture_value: Tag = .{ .kind = .exif, .num = 0x9202 };
    pub const brightness_value: Tag = .{ .kind = .exif, .num = 0x9203 };
    pub const exposure_bias_value: Tag = .{ .kind = .exif, .num = 0x9204 };
    pub const max_aperture_value: Tag = .{ .kind = .exif, .num = 0x9205 };
    pub const subject_distance: Tag = .{ .kind = .exif, .num = 0x9206 };
    pub const metering_mode: Tag = .{ .kind = .exif, .num = 0x9207 };
    pub const light_source: Tag = .{ .kind = .exif, .num = 0x9208 };
    pub const flash: Tag = .{ .kind = .exif, .num = 0x9209 };
    pub const focal_length: Tag = .{ .kind = .exif, .num = 0x920A };
    pub const subject_area: Tag = .{ .kind = .exif, .num = 0x9214 };
    pub const maker_note: Tag = .{ .kind = .exif, .num = 0x927C };
    pub const user_comment: Tag = .{ .kind = .exif, .num = 0x9286 };
    pub const sub_sec_time: Tag = .{ .kind = .exif, .num = 0x9290 };
    pub const sub_sec_time_original: Tag = .{ .kind = .exif, .num = 0x9291 };
    pub const sub_sec_time_digitized: Tag = .{ .kind = .exif, .num = 0x9292 };
    pub const flashpix_version: Tag = .{ .kind = .exif, .num = 0xA000 };
    pub const color_space: Tag = .{ .kind = .exif, .num = 0xA001 };
    pub const pixel_x_dimension: Tag = .{ .kind = .exif, .num = 0xA002 };
    pub const pixel_y_dimension: Tag = .{ .kind = .exif, .num = 0xA003 };
    pub const related_sound_file: Tag = .{ .kind = .exif, .num = 0xA004 };
    pub const flash_energy: Tag = .{ .kind = .exif, .num = 0xA20B };
    pub const focal_plane_x_resolution: Tag = .{ .kind = .exif, .num = 0xA20E };
    pub const focal_plane_y_resolution: Tag = .{ .kind = .exif, .num = 0xA20F };
    pub const focal_plane_resolution_unit: Tag = .{ .kind = .exif, .num = 0xA210 };
    pub const subject_location: Tag = .{ .kind = .exif, .num = 0xA214 };
    pub const exposure_index: Tag = .{ .kind = .exif, .num = 0xA215 };
    pub const sensing_method: Tag = .{ .kind = .exif, .num = 0xA217 };
    pub const file_source: Tag = .{ .kind = .exif, .num = 0xA300 };
    pub const scene_type: Tag = .{ .kind = .exif, .num = 0xA301 };
    pub const cfa_pattern: Tag = .{ .kind = .exif, .num = 0xA302 };
    pub const custom_rendered: Tag = .{ .kind = .exif, .num = 0xA401 };
    pub const exposure_mode: Tag = .{ .kind = .exif, .num = 0xA402 };
    pub const white_balance: Tag = .{ .kind = .exif, .num = 0xA403 };
    pub const digital_zoom_ratio: Tag = .{ .kind = .exif, .num = 0xA404 };
    pub const focal_length_in_35mm_film: Tag = .{ .kind = .exif, .num = 0xA405 };
    pub const scene_capture_type: Tag = .{ .kind = .exif, .num = 0xA406 };
    pub const gain_control: Tag = .{ .kind = .exif, .num = 0xA407 };
    pub const contrast: Tag = .{ .kind = .exif, .num = 0xA408 };
    pub const saturation: Tag = .{ .kind = .exif, .num = 0xA409 };
    pub const sharpness: Tag = .{ .kind = .exif, .num = 0xA40A };
    pub const subject_distance_range: Tag = .{ .kind = .exif, .num = 0xA40C };
    pub const image_unique_id: Tag = .{ .kind = .exif, .num = 0xA420 };
    pub const camera_owner_name: Tag = .{ .kind = .exif, .num = 0xA430 };
    pub const body_serial_number: Tag = .{ .kind = .exif, .num = 0xA431 };
    pub const lens_specification: Tag = .{ .kind = .exif, .num = 0xA432 };
    pub const lens_make: Tag = .{ .kind = .exif, .num = 0xA433 };
    pub const lens_model: Tag = .{ .kind = .exif, .num = 0xA434 };
    pub const lens_serial_number: Tag = .{ .kind = .exif, .num = 0xA435 };
    pub const gamma: Tag = .{ .kind = .exif, .num = 0xA500 };

    // GPS IFD
    pub const gps_version_id: Tag = .{ .kind = .gps, .num = 0x0000 };
    pub const gps_latitude_ref: Tag = .{ .kind = .gps, .num = 0x0001 };
    pub const gps_latitude: Tag = .{ .kind = .gps, .num = 0x0002 };
    pub const gps_longitude_ref: Tag = .{ .kind = .gps, .num = 0x0003 };
    pub const gps_longitude: Tag = .{ .kind = .gps, .num = 0x0004 };
    pub const gps_altitude_ref: Tag = .{ .kind = .gps, .num = 0x0005 };
    pub const gps_altitude: Tag = .{ .kind = .gps, .num = 0x0006 };
    pub const gps_time_stamp: Tag = .{ .kind = .gps, .num = 0x0007 };
    pub const gps_satellites: Tag = .{ .kind = .gps, .num = 0x0008 };
    pub const gps_status: Tag = .{ .kind = .gps, .num = 0x0009 };
    pub const gps_measure_mode: Tag = .{ .kind = .gps, .num = 0x000A };
    pub const gps_dop: Tag = .{ .kind = .gps, .num = 0x000B };
    pub const gps_speed_ref: Tag = .{ .kind = .gps, .num = 0x000C };
    pub const gps_speed: Tag = .{ .kind = .gps, .num = 0x000D };
    pub const gps_track_ref: Tag = .{ .kind = .gps, .num = 0x000E };
    pub const gps_track: Tag = .{ .kind = .gps, .num = 0x000F };
    pub const gps_img_direction_ref: Tag = .{ .kind = .gps, .num = 0x0010 };
    pub const gps_img_direction: Tag = .{ .kind = .gps, .num = 0x0011 };
    pub const gps_map_datum: Tag = .{ .kind = .gps, .num = 0x0012 };
    pub const gps_dest_latitude_ref: Tag = .{ .kind = .gps, .num = 0x0013 };
    pub const gps_dest_latitude: Tag = .{ .kind = .gps, .num = 0x0014 };
    pub const gps_dest_longitude_ref: Tag = .{ .kind = .gps, .num = 0x0015 };
    pub const gps_dest_longitude: Tag = .{ .kind = .gps, .num = 0x0016 };
    pub const gps_dest_bearing_ref: Tag = .{ .kind = .gps, .num = 0x0017 };
    pub const gps_dest_bearing: Tag = .{ .kind = .gps, .num = 0x0018 };
    pub const gps_dest_distance_ref: Tag = .{ .kind = .gps, .num = 0x0019 };
    pub const gps_dest_distance: Tag = .{ .kind = .gps, .num = 0x001A };
    pub const gps_processing_method: Tag = .{ .kind = .gps, .num = 0x001B };
    pub const gps_area_information: Tag = .{ .kind = .gps, .num = 0x001C };
    pub const gps_date_stamp: Tag = .{ .kind = .gps, .num = 0x001D };
    pub const gps_differential: Tag = .{ .kind = .gps, .num = 0x001E };
    pub const gps_h_positioning_error: Tag = .{ .kind = .gps, .num = 0x001F };

    // Interoperability IFD
    pub const interoperability_index: Tag = .{ .kind = .interop, .num = 0x0001 };
    pub const interoperability_version: Tag = .{ .kind = .interop, .num = 0x0002 };
};

pub const TagInfo = struct {
    tag: Tag,
    name: []const u8,
    /// Type used when writing the tag from text (e.g. by the CLI).
    type: Type,
};

fn t(tag: Tag, tag_name: []const u8, ty: Type) TagInfo {
    return .{ .tag = tag, .name = tag_name, .type = ty };
}

/// Pointer tags. They are managed by the library and never appear as entries.
pub const exif_ifd_pointer: u16 = 0x8769;
pub const gps_ifd_pointer: u16 = 0x8825;
pub const interop_ifd_pointer: u16 = 0xA005;
pub const thumbnail_offset: u16 = 0x0201;
pub const thumbnail_length: u16 = 0x0202;

/// All known tags.
pub const table = [_]TagInfo{
    // IFD0 (TIFF) tags. Also valid in IFD1, see `in`.
    t(.image_width, "ImageWidth", .long),
    t(.image_length, "ImageLength", .long),
    t(.bits_per_sample, "BitsPerSample", .short),
    t(.compression, "Compression", .short),
    t(.photometric_interpretation, "PhotometricInterpretation", .short),
    t(.image_description, "ImageDescription", .ascii),
    t(.make, "Make", .ascii),
    t(.model, "Model", .ascii),
    t(.orientation, "Orientation", .short),
    t(.samples_per_pixel, "SamplesPerPixel", .short),
    t(.x_resolution, "XResolution", .rational),
    t(.y_resolution, "YResolution", .rational),
    t(.planar_configuration, "PlanarConfiguration", .short),
    t(.resolution_unit, "ResolutionUnit", .short),
    t(.transfer_function, "TransferFunction", .short),
    t(.software, "Software", .ascii),
    t(.date_time, "DateTime", .ascii),
    t(.artist, "Artist", .ascii),
    t(.white_point, "WhitePoint", .rational),
    t(.primary_chromaticities, "PrimaryChromaticities", .rational),
    t(.ycbcr_coefficients, "YCbCrCoefficients", .rational),
    t(.ycbcr_sub_sampling, "YCbCrSubSampling", .short),
    t(.ycbcr_positioning, "YCbCrPositioning", .short),
    t(.reference_black_white, "ReferenceBlackWhite", .rational),
    t(.rating, "Rating", .short),
    t(.copyright, "Copyright", .ascii),
    t(.xp_title, "XPTitle", .byte),
    t(.xp_comment, "XPComment", .byte),
    t(.xp_author, "XPAuthor", .byte),
    t(.xp_keywords, "XPKeywords", .byte),
    t(.xp_subject, "XPSubject", .byte),

    // Exif IFD
    t(.exposure_time, "ExposureTime", .rational),
    t(.f_number, "FNumber", .rational),
    t(.exposure_program, "ExposureProgram", .short),
    t(.spectral_sensitivity, "SpectralSensitivity", .ascii),
    t(.iso_speed_ratings, "ISOSpeedRatings", .short),
    t(.oecf, "OECF", .undefined),
    t(.sensitivity_type, "SensitivityType", .short),
    t(.exif_version, "ExifVersion", .undefined),
    t(.date_time_original, "DateTimeOriginal", .ascii),
    t(.date_time_digitized, "DateTimeDigitized", .ascii),
    t(.offset_time, "OffsetTime", .ascii),
    t(.offset_time_original, "OffsetTimeOriginal", .ascii),
    t(.offset_time_digitized, "OffsetTimeDigitized", .ascii),
    t(.components_configuration, "ComponentsConfiguration", .undefined),
    t(.compressed_bits_per_pixel, "CompressedBitsPerPixel", .rational),
    t(.shutter_speed_value, "ShutterSpeedValue", .srational),
    t(.aperture_value, "ApertureValue", .rational),
    t(.brightness_value, "BrightnessValue", .srational),
    t(.exposure_bias_value, "ExposureBiasValue", .srational),
    t(.max_aperture_value, "MaxApertureValue", .rational),
    t(.subject_distance, "SubjectDistance", .rational),
    t(.metering_mode, "MeteringMode", .short),
    t(.light_source, "LightSource", .short),
    t(.flash, "Flash", .short),
    t(.focal_length, "FocalLength", .rational),
    t(.subject_area, "SubjectArea", .short),
    t(.maker_note, "MakerNote", .undefined),
    t(.user_comment, "UserComment", .undefined),
    t(.sub_sec_time, "SubSecTime", .ascii),
    t(.sub_sec_time_original, "SubSecTimeOriginal", .ascii),
    t(.sub_sec_time_digitized, "SubSecTimeDigitized", .ascii),
    t(.flashpix_version, "FlashpixVersion", .undefined),
    t(.color_space, "ColorSpace", .short),
    t(.pixel_x_dimension, "PixelXDimension", .long),
    t(.pixel_y_dimension, "PixelYDimension", .long),
    t(.related_sound_file, "RelatedSoundFile", .ascii),
    t(.flash_energy, "FlashEnergy", .rational),
    t(.focal_plane_x_resolution, "FocalPlaneXResolution", .rational),
    t(.focal_plane_y_resolution, "FocalPlaneYResolution", .rational),
    t(.focal_plane_resolution_unit, "FocalPlaneResolutionUnit", .short),
    t(.subject_location, "SubjectLocation", .short),
    t(.exposure_index, "ExposureIndex", .rational),
    t(.sensing_method, "SensingMethod", .short),
    t(.file_source, "FileSource", .undefined),
    t(.scene_type, "SceneType", .undefined),
    t(.cfa_pattern, "CFAPattern", .undefined),
    t(.custom_rendered, "CustomRendered", .short),
    t(.exposure_mode, "ExposureMode", .short),
    t(.white_balance, "WhiteBalance", .short),
    t(.digital_zoom_ratio, "DigitalZoomRatio", .rational),
    t(.focal_length_in_35mm_film, "FocalLengthIn35mmFilm", .short),
    t(.scene_capture_type, "SceneCaptureType", .short),
    t(.gain_control, "GainControl", .short),
    t(.contrast, "Contrast", .short),
    t(.saturation, "Saturation", .short),
    t(.sharpness, "Sharpness", .short),
    t(.subject_distance_range, "SubjectDistanceRange", .short),
    t(.image_unique_id, "ImageUniqueID", .ascii),
    t(.camera_owner_name, "CameraOwnerName", .ascii),
    t(.body_serial_number, "BodySerialNumber", .ascii),
    t(.lens_specification, "LensSpecification", .rational),
    t(.lens_make, "LensMake", .ascii),
    t(.lens_model, "LensModel", .ascii),
    t(.lens_serial_number, "LensSerialNumber", .ascii),
    t(.gamma, "Gamma", .rational),

    // GPS IFD
    t(.gps_version_id, "GPSVersionID", .byte),
    t(.gps_latitude_ref, "GPSLatitudeRef", .ascii),
    t(.gps_latitude, "GPSLatitude", .rational),
    t(.gps_longitude_ref, "GPSLongitudeRef", .ascii),
    t(.gps_longitude, "GPSLongitude", .rational),
    t(.gps_altitude_ref, "GPSAltitudeRef", .byte),
    t(.gps_altitude, "GPSAltitude", .rational),
    t(.gps_time_stamp, "GPSTimeStamp", .rational),
    t(.gps_satellites, "GPSSatellites", .ascii),
    t(.gps_status, "GPSStatus", .ascii),
    t(.gps_measure_mode, "GPSMeasureMode", .ascii),
    t(.gps_dop, "GPSDOP", .rational),
    t(.gps_speed_ref, "GPSSpeedRef", .ascii),
    t(.gps_speed, "GPSSpeed", .rational),
    t(.gps_track_ref, "GPSTrackRef", .ascii),
    t(.gps_track, "GPSTrack", .rational),
    t(.gps_img_direction_ref, "GPSImgDirectionRef", .ascii),
    t(.gps_img_direction, "GPSImgDirection", .rational),
    t(.gps_map_datum, "GPSMapDatum", .ascii),
    t(.gps_dest_latitude_ref, "GPSDestLatitudeRef", .ascii),
    t(.gps_dest_latitude, "GPSDestLatitude", .rational),
    t(.gps_dest_longitude_ref, "GPSDestLongitudeRef", .ascii),
    t(.gps_dest_longitude, "GPSDestLongitude", .rational),
    t(.gps_dest_bearing_ref, "GPSDestBearingRef", .ascii),
    t(.gps_dest_bearing, "GPSDestBearing", .rational),
    t(.gps_dest_distance_ref, "GPSDestDistanceRef", .ascii),
    t(.gps_dest_distance, "GPSDestDistance", .rational),
    t(.gps_processing_method, "GPSProcessingMethod", .undefined),
    t(.gps_area_information, "GPSAreaInformation", .undefined),
    t(.gps_date_stamp, "GPSDateStamp", .ascii),
    t(.gps_differential, "GPSDifferential", .short),
    t(.gps_h_positioning_error, "GPSHPositioningError", .rational),

    // Interoperability IFD
    t(.interoperability_index, "InteroperabilityIndex", .ascii),
    t(.interoperability_version, "InteroperabilityVersion", .undefined),
};

/// Finds a tag by its EXIF name, case-insensitive (e.g. "DateTimeOriginal").
/// IFD0 tags are returned in IFD0; use `Tag.in(.ifd1)` for the thumbnail IFD.
pub fn find(needle: []const u8) ?TagInfo {
    for (table) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, needle)) return entry;
    }
    return null;
}

/// Looks up a tag's info. IFD1 tags resolve to their IFD0 counterparts.
pub fn info(tag: Tag) ?TagInfo {
    const kind: IfdKind = if (tag.kind == .ifd1) .ifd0 else tag.kind;
    for (table) |entry| {
        if (entry.tag.kind == kind and entry.tag.num == tag.num) return entry;
    }
    return null;
}

/// Returns the tag's EXIF name, or null if unknown.
pub fn name(tag: Tag) ?[]const u8 {
    return if (info(tag)) |i| i.name else null;
}

test "named constants" {
    try std.testing.expectEqual(@as(u16, 0x829A), Tag.exposure_time.num);
    try std.testing.expectEqual(IfdKind.exif, Tag.exposure_time.kind);
    try std.testing.expect(Tag.orientation.in(.ifd1).eql(.{ .kind = .ifd1, .num = 0x0112 }));
}

test "find and name" {
    const make = find("make").?;
    try std.testing.expect(make.tag.eql(.make));
    try std.testing.expectEqualStrings("GPSLatitude", name(.gps_latitude).?);
    try std.testing.expectEqualStrings("Orientation", name(Tag.orientation.in(.ifd1)).?);
    try std.testing.expect(find("NoSuchTag") == null);
}

test "table has no duplicate tags" {
    for (table, 0..) |a, i| for (table[i + 1 ..]) |b| {
        try std.testing.expect(!a.tag.eql(b.tag));
        try std.testing.expect(!std.mem.eql(u8, a.name, b.name));
    };
}
