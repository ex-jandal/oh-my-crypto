const KeyError = error{
    NotValidKey,
};

pub fn Cipher(comptime Algorithm: type) type {
    return struct {
        ctx: Algorithm,

        pub fn init(args: anytype) KeyError!@This() {
            return .{ .ctx = try @call(.auto, Algorithm.init, args) };
        }

        pub inline fn encrypt(self: @This(), plaintext: []const u8, buf: []u8) void {
            if (comptime !@hasDecl(Algorithm, "encrypt")) {
                @compileError(@typeName(Algorithm) ++ " must implement `pub fn encrypt(self, plaintext, buf)`");
            }
            self.ctx.encrypt(plaintext, buf);
        }

        pub inline fn decrypt(self: @This(), ciphertext: []const u8, buf: []u8) void {
            if (comptime !@hasDecl(Algorithm, "decrypt")) {
                @compileError(@typeName(Algorithm) ++ " must implement `pub fn decrypt(self, ciphertext, buf)`");
            }
            self.ctx.decrypt(ciphertext, buf);
        }
    };
}

pub const Caesar = struct {
    shift: u8,

    pub fn init(shift: u8) KeyError!Caesar {
        return .{ .shift = @mod(shift, 26) };
    }

    pub fn encrypt(self: Caesar, plaintxt: []const u8, buf: []u8) void {
        for (plaintxt, 0..) |c, idx| {
            if (c >= 'a' and c <= 'z') {
                buf[idx] = @mod((c - 'a') + self.shift, 26) + 'a';
            } else if (c >= 'A' and c <= 'Z') {
                buf[idx] = @mod((c - 'A') + self.shift, 26) + 'A';
            } else {
                buf[idx] = c;
            }
        }
    }

    pub fn decrypt(self: Caesar, ciphertxt: []const u8, buf: []u8) void {
        for (ciphertxt, 0..) |c, idx| {
            if (c >= 'a' and c <= 'z') {
                buf[idx] = @mod((c - 'a') - self.shift, 26) + 'a';
            } else if (c >= 'A' and c <= 'Z') {
                buf[idx] = @mod((c - 'A') - self.shift, 26) + 'A';
            } else {
                buf[idx] = c;
            }
        }
    }
};

pub const Multiplicative = struct {
    key: u8,
    key_inv: u8,

    pub fn init(key: u8) KeyError!Multiplicative {
        if (invert_key(key)) |value| {
            return .{ 
                .key = @mod(key, 26),
                .key_inv = value,
            };
        }
        return KeyError.NotValidKey;
    }

    pub fn encrypt(self: Multiplicative, plaintxt: []const u8, buf: []u8) void {
        for (plaintxt, 0..) |c, idx| {
            if (c >= 'a' and c <= 'z') {
                buf[idx] = @mod((c - 'a') * self.key, 26) + 'a';
            } else if (c >= 'A' and c <= 'Z') {
                buf[idx] = @mod((c - 'A') * self.key, 26) + 'A';
            } else {
                buf[idx] = c;
            }
        }
    }

    pub fn decrypt(self: Multiplicative, ciphertxt: []const u8, buf: []u8) void {
        for (ciphertxt, 0..) |c, idx| {
            if (c >= 'a' and c <= 'z') {
                buf[idx] = @mod((c - 'a') * self.key_inv, 26) + 'a';
            } else if (c >= 'A' and c <= 'Z') {
                buf[idx] = @mod((c - 'A') * self.key_inv, 26) + 'A';
            } else {
                buf[idx] = c;
            }
        }
    }

    pub fn invert_key(a: u8) ?u8 {
        const lut = [26]?u8{
            null, 1,    null, 9,    null, 21,   null, 15,
            null, 3,    null, 19,   null, null, null, 7,
            null, 23,   null, 11,   null, 5,    null, 17,
            null, 25,
        };
        return lut[@mod(a, 26)];
    }
};

pub const Affine = struct {
    key_1: u8,
    key_2: u8,
    key_inv: u8,

    pub fn init(key_1: u8, key_2: u8) KeyError!Affine {
        if (invert_key(key_1)) |key_1_inv| {
            return .{ 
                .key_1 = key_1,
                .key_2 = key_2,
                .key_inv = key_1_inv,
            };
        }
        return KeyError.NotValidKey;
    }

    pub fn encrypt(self: Affine, plaintxt: []const u8, buf: []u8) void {
        for (plaintxt, 0..) |c, idx| {
            if (c >= 'a' and c <= 'z') {
                buf[idx] = @mod(((c - 'a') * self.key_1) + self.key_2, 26) + 'a';
            } else if (c >= 'A' and c <= 'Z') {
                buf[idx] = @mod(((c - 'A') * self.key_1) + self.key_2, 26) + 'A';
            } else {
                buf[idx] = c;
            }
        }
    }

    pub fn decrypt(self: Affine, ciphertxt: []const u8, buf: []u8) void {
        for (ciphertxt, 0..) |c, idx| {
            if (c >= 'a' and c <= 'z') {
                const char_val: i32 = c - 'a';
                const temp_k2: i32 = @intCast(self.key_2);
                const temp_k_inv: i32 = @intCast(self.key_inv);
                
                const decrypted = @mod((char_val - temp_k2) * temp_k_inv, 26);
                buf[idx] = @intCast(decrypted + 'a');

            } else if (c >= 'A' and c <= 'Z') {
                const char_val: i32 = c - 'A';
                const temp_k2: i32 = @intCast(self.key_2);
                const temp_k_inv: i32 = @intCast(self.key_inv);

                const decrypted = @mod((char_val - temp_k2) * temp_k_inv, 26);
                buf[idx] = @intCast(decrypted + 'A');

            } else {
                buf[idx] = c;
            }
        }
    }

    pub fn invert_key(a: u8) ?u8 {
        const lut = [26]?u8{
            null, 1,    null, 9,    null, 21,   null, 15,
            null, 3,    null, 19,   null, null, null, 7,
            null, 23,   null, 11,   null, 5,    null, 17,
            null, 25,
        };
        return lut[@mod(a, 26)];
    }
};

test "Caesar cipher" {
    const std = @import("std");

    const C = try Cipher(Caesar).init(.{3});
    var buf = [_]u8{0} ** 11;

    C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Khoor Zruog", &buf);

    C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Multiplicative cipher" {
    const std = @import("std");

    const C = try Cipher(Multiplicative).init(.{3});
    var buf = [_]u8{0} ** 11;

    C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Vmhhq Oqzhj", &buf);

    C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);

    const C_err = Cipher(Multiplicative).init(.{2});
    try std.testing.expectError(KeyError.NotValidKey, C_err);
}

test "Affine cipher" {
    const std = @import("std");

    const C = try Cipher(Affine).init(.{3, 9});
    var buf = [_]u8{0} ** 11;

    C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Evqqz Xziqs", &buf);

    C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);

    const C_err = Cipher(Multiplicative).init(.{2});
    try std.testing.expectError(KeyError.NotValidKey, C_err);
}
