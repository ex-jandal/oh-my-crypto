const std = @import("std");
const zigimg = @import("zigimg");

const Managed = zigimg.Image.Managed;
const Rgba32 = zigimg.color.Rgba32;

pub const ImageHandle = Managed;

pub const Error = error{
    ImageNotLoaded,
    TextTooLong,
    NoHiddenMessage,
    LoadFailed,
    SaveFailed,
};

const header_len = 4;
const bits_per_channel = 8;
const channels_per_pixel = 3;

pub fn capacity(image: *const Managed) usize {
    return (image.width * image.height * channels_per_pixel) / bits_per_channel;
}

pub fn loadFromRaw(allocator: std.mem.Allocator, pixels: []const u8, w: usize, h: usize, out: *Managed) Error!void {
    out.* = Managed.fromRawPixels(allocator, w, h, pixels, .rgba32) catch return Error.LoadFailed;
}

pub fn deinit(image: *Managed) void {
    image.deinit();
}

pub fn toRgba32(image: *Managed) Error!void {
    if (image.pixelFormat() != .rgba32) {
        image.convert(.rgba32) catch return Error.LoadFailed;
    }
}

pub fn rgbaBytes(image: *const Managed) []const u8 {
    return switch (image.pixels) {
        .rgba32 => |p| std.mem.sliceAsBytes(p),
        else => &.{},
    };
}

pub fn width(image: *const Managed) i32 {
    return @intCast(image.width);
}

pub fn height(image: *const Managed) i32 {
    return @intCast(image.height);
}

pub fn embed(image: *Managed, text: []const u8) Error!void {
    try toRgba32(image);
    const total_bytes = header_len + text.len;
    if (total_bytes > capacity(image)) return Error.TextTooLong;

    const data = switch (image.pixels) {
        .rgba32 => |p| p,
        else => unreachable,
    };

    var bit_index: usize = 0;
    const len_bytes = littleEndian(@as(u32, @intCast(text.len)));
    for (len_bytes) |byte| {
        embedByte(data, bit_index, byte);
        bit_index += 8;
    }
    for (text) |byte| {
        embedByte(data, bit_index, byte);
        bit_index += 8;
    }
}

pub fn extract(allocator: std.mem.Allocator, image: *Managed) Error![]u8 {
    if (image.width == 0 or image.height == 0) return Error.ImageNotLoaded;
    try toRgba32(image);
    if (capacity(image) < header_len) return Error.NoHiddenMessage;

    const data = switch (image.pixels) {
        .rgba32 => |p| p,
        else => unreachable,
    };

    var header: [header_len]u8 = undefined;
    var bit_index: usize = 0;
    for (&header) |*byte| {
        byte.* = extractByte(data, bit_index);
        bit_index += 8;
    }
    const msg_len = u32FromLittleEndian(header);
    if (msg_len > capacity(image) - header_len) return Error.NoHiddenMessage;

    const out = allocator.alloc(u8, msg_len) catch return Error.NoHiddenMessage;
    for (out) |*byte| {
        byte.* = extractByte(data, bit_index);
        bit_index += 8;
    }
    return out;
}

fn setChannel(px: *Rgba32, channel: usize, bit: u8) void {
    switch (channel) {
        0 => px.r = (px.r & 0xFE) | bit,
        1 => px.g = (px.g & 0xFE) | bit,
        else => px.b = (px.b & 0xFE) | bit,
    }
}

fn getChannel(px: Rgba32, channel: usize) u8 {
    return switch (channel) {
        0 => px.r & 1,
        1 => px.g & 1,
        else => px.b & 1,
    };
}

fn embedByte(data: []Rgba32, bit_index: usize, byte: u8) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const position = bit_index + i;
        const channel = position % channels_per_pixel;
        const pixel = position / channels_per_pixel;
        const shift_amt: u3 = @intCast(7 - i);
        const bit: u8 = @intCast((byte >> shift_amt) & 1);
        setChannel(&data[pixel], channel, bit);
    }
}

fn extractByte(data: []const Rgba32, bit_index: usize) u8 {
    var i: usize = 0;
    var acc: u8 = 0;
    while (i < 8) : (i += 1) {
        const position = bit_index + i;
        const channel = position % channels_per_pixel;
        const pixel = position / channels_per_pixel;
        const bit = getChannel(data[pixel], channel);
        acc = (acc << 1) | bit;
    }
    return acc;
}

fn littleEndian(value: u32) [4]u8 {
    return .{
        @intCast(value & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 24) & 0xff),
    };
}

fn u32FromLittleEndian(bytes: [4]u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

test "embed/extract round trip" {
    var image = try Managed.create(std.testing.allocator, 32, 32, .rgba32);
    defer image.deinit();
    const msg = "secret message 123";
    try embed(&image, msg);
    const out = try extract(std.testing.allocator, &image);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualSlices(u8, msg, out);
}
