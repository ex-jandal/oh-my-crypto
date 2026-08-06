const std = @import("std");

const KeyError = error{
    InvalidKey,
    NoKeyProvided,
    InvalidRails,
};

pub fn Cipher(comptime Algorithm: type) type {
    return struct {
        ctx: Algorithm,

        pub fn init(args: anytype) KeyError!@This() {
            return .{ .ctx = try @call(.auto, Algorithm.init, args) };
        }

        pub inline fn encrypt(self: @This(), plaintext: []const u8, buf: []u8) !void {
            if (comptime !@hasDecl(Algorithm, "encrypt")) {
                @compileError(@typeName(Algorithm) ++ " must implement `pub fn encrypt(self, plaintext, buf)`");
            }
            try self.ctx.encrypt(plaintext, buf);
        }

        pub inline fn decrypt(self: @This(), ciphertext: []const u8, buf: []u8) !void {
            if (comptime !@hasDecl(Algorithm, "decrypt")) {
                @compileError(@typeName(Algorithm) ++ " must implement `pub fn decrypt(self, ciphertext, buf)`");
            }
            try self.ctx.decrypt(ciphertext, buf);
        }
    };
}

pub const Caesar = struct {
    shift: u8,

    pub fn init(shift: u8) KeyError!Caesar {
        return .{ .shift = @mod(shift, 26) };
    }

    pub fn encrypt(self: Caesar, plaintxt: []const u8, buf: []u8) !void {
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

    pub fn decrypt(self: Caesar, ciphertxt: []const u8, buf: []u8) !void {
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
        return KeyError.InvalidKey;
    }

    pub fn encrypt(self: Multiplicative, plaintxt: []const u8, buf: []u8) !void {
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

    pub fn decrypt(self: Multiplicative, ciphertxt: []const u8, buf: []u8) !void {
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
        return KeyError.InvalidKey;
    }

    pub fn encrypt(self: Affine, plaintxt: []const u8, buf: []u8) !void {
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

    pub fn decrypt(self: Affine, ciphertxt: []const u8, buf: []u8) !void {
        for (ciphertxt, 0..) |c, idx| {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                buf[idx] = c;
                continue;
            }

            const temp_k2: i16 = @intCast(self.key_2);
            const temp_k_inv: i16 = @intCast(self.key_inv);

            if (c >= 'a' and c <= 'z') {
                const char_val: i16 = c - 'a';
                
                const decrypted = @mod((char_val - temp_k2) * temp_k_inv, 26);
                buf[idx] = @intCast(decrypted + 'a');

            } else {
                const char_val: i16 = c - 'A';

                const decrypted = @mod((char_val - temp_k2) * temp_k_inv, 26);
                buf[idx] = @intCast(decrypted + 'A');

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

pub const Autokey = struct {
    allocator: std.mem.Allocator,
    key: []const u8,

    pub fn init(allocator: std.mem.Allocator, key: []const u8) KeyError!Autokey {
        if (key.len == 0) 
            return KeyError.NoKeyProvided;

        return .{ 
            .key = key,
            .allocator = allocator,
        };
    }

    pub fn encrypt(self: Autokey, plaintxt: []const u8, buf: []u8) !void {
        const full_key = try self.allocator.alloc(
            u8,
            if (self.key.len > plaintxt.len) self.key.len 
            else plaintxt.len,
        );
        defer self.allocator.free(full_key);

        @memcpy(full_key[0..self.key.len], self.key);
        if (!(plaintxt.len < self.key.len)) {
            @memcpy(full_key[self.key.len..], plaintxt[0..(plaintxt.len - self.key.len)]);
        }

        const cleared_key = clear_str(full_key);

        var key_idx: u8 = 0;
        for (plaintxt, 0..) |c, idx| {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                buf[idx] = c;
                continue;
            }

            var key = 
                if (key_idx < cleared_key.len)
                    full_key[key_idx]
                else 
                    full_key[key_idx - cleared_key.len];
            key = 
                if (key >= 'a' and key <= 'z')
                    key - 'a'
                else
                    key - 'A';

            if (c >= 'a' and c <= 'z') {
                buf[idx] = @mod((c - 'a') + key, 26) + 'a';
            } else {
                buf[idx] = @mod((c - 'A') + key, 26) + 'A';
            }
            key_idx += 1;
        }
    }

    pub fn decrypt(self: Autokey, ciphertxt: []const u8, buf: []u8) !void {
        var last_chr_buf: u8 = undefined;

        var key_idx: u8 = 0;
        for (ciphertxt, 0..) |c, idx| {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                buf[idx] = c;
                continue;
            }

            var key = 
                if (key_idx < self.key.len)
                    @as(i16, self.key[idx])
                else
                    @as(i16, last_chr_buf);

            key = 
                if (key >= 'a' and key <= 'z')
                    @as(i16, key - 'a')
                else
                    @as(i16, key - 'A');

            if (c >= 'a' and c <= 'z') {
                const dec_chr: u8 = @intCast(@mod(@as(i16, c - 'a') - key, 26) + 'a');
                buf[idx] = dec_chr;
            } else {
                const dec_chr: u8 = @intCast(@mod(@as(i16, c - 'A') - key, 26) + 'A');
                buf[idx] = dec_chr;
            }
            last_chr_buf = buf[idx];
            key_idx += 1;
        }
    }
};

pub const Viegener = struct {
    key: []const u8,

    pub fn init(key: []const u8) KeyError!Viegener {
        if (key.len == 0) 
            return KeyError.NoKeyProvided;

        return .{ 
            .key = key,
        };
    }

    pub fn encrypt(self: Viegener, plaintxt: []const u8, buf: []u8) !void {
        var key_idx: u8 = 0;
        for (plaintxt, 0..) |c, idx| {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                buf[idx] = c;
                continue;
            }

            var key_chr = self.key[key_idx % self.key.len];
            key_chr = 
                if (key_chr >= 'a' and key_chr <= 'z')
                    key_chr - 'a'
                else
                    key_chr - 'A';

            if (c >= 'a' and c <= 'z') {
                buf[idx] = @mod((c - 'a') + key_chr, 26) + 'a';
            } else {
                buf[idx] = @mod((c - 'A') + key_chr, 26) + 'A';
            }
            key_idx += 1;
        }
    }

    pub fn decrypt(self: Viegener, ciphertxt: []const u8, buf: []u8) !void {
        var key_idx: u8 = 0;
        for (ciphertxt, 0..) |c, idx| {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                buf[idx] = c;
                continue;
            }

            var key: i16 = self.key[key_idx % self.key.len];

            key = 
                if (key >= 'a' and key <= 'z')
                    key - 'a'
                else
                    key - 'A';

            if (c >= 'a' and c <= 'z') {
                const dec_chr: u8 = @intCast(@mod(@as(i16, c - 'a') - key, 26) + 'a');
                buf[idx] = dec_chr;
            } else {
                const dec_chr: u8 = @intCast(@mod(@as(i16, c - 'A') - key, 26) + 'A');
                buf[idx] = dec_chr;
            }
            key_idx += 1;
        }
    }
};

pub const Zigzag = struct {
    rails: u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, rails: u8) KeyError!Zigzag {
        if (rails < 2) return KeyError.InvalidRails;

        return .{ 
            .rails = rails,
            .allocator = allocator,
        };
    }

    pub fn encrypt(self: Zigzag, plaintxt: []const u8, buf: []u8) !void {
        var row_counts = try self.allocator.alloc(u8, self.rails);
        defer self.allocator.free(row_counts);

        @memset(row_counts, 0);

        for (plaintxt, 0..) |c, i| {
            if (!std.ascii.isAlphabetic(c))
                continue;

            row_counts[self.rail_at(@intCast(i))] += 1;
        }

        var offsets = try self.allocator.alloc(u8, self.rails);
        defer self.allocator.free(offsets);

        offsets[0] = 0;
        for (1..self.rails) |r| {
            offsets[r] = offsets[r - 1] + row_counts[r - 1];
        }

        for (plaintxt, 0..) |c, i| {
            if (!std.ascii.isAlphabetic(c)) {
                continue;
            }

            const rail = self.rail_at(@intCast(i));
            buf[offsets[rail]] = c;
            offsets[rail] += 1;
        }

        try self.restore_formatting(plaintxt, buf);
    }

    pub fn decrypt(self: Zigzag, ciphertxt: []const u8, buf: []u8) !void {
        // 1. Extract only the raw cipher letters (which were packed rail-by-rail in `encrypt`)
        const clean_cipher = try self.allocator.alloc(u8, ciphertxt.len);
        defer self.allocator.free(clean_cipher);

        var clean_len: usize = 0;
        for (ciphertxt) |c| {
            if (std.ascii.isAlphabetic(c)) {
                clean_cipher[clean_len] = c;
                clean_len += 1;
            }
        }

        // 2. Count letters per rail using `i` (matching `encrypt`'s exact indexing!)
        const row_counts = try self.allocator.alloc(usize, self.rails);
        defer self.allocator.free(row_counts);
        @memset(row_counts, 0);

        for (ciphertxt, 0..) |c, i| {
            if (std.ascii.isAlphabetic(c)) {
                row_counts[self.rail_at(i)] += 1;
            }
        }

        // 3. Rebuild rail partition offsets inside `clean_cipher`
        const offsets = try self.allocator.alloc(usize, self.rails);
        defer self.allocator.free(offsets);

        offsets[0] = 0;
        for (1..self.rails) |r| {
            offsets[r] = offsets[r - 1] + row_counts[r - 1];
        }

        // 4. Reconstruct original text into output buffer
        for (ciphertxt, 0..) |c, i| {
            if (std.ascii.isAlphabetic(c)) {
                const rail = self.rail_at(i);
                buf[i] = clean_cipher[offsets[rail]];
                offsets[rail] += 1;
            } else {
                buf[i] = c;
            }
        }
    }

    fn rail_at(self: Zigzag, i: usize) usize {
        const mid = self.rails - 1;
        const pos = i % (2 * mid);
        return if (pos < mid) pos else 2 * mid - pos;
    }

    fn restore_formatting(
        self: Zigzag,
        plaintxt: []const u8,
        ciphertxt: []u8,
    ) !void {
        const buf = try self.allocator.alloc(u8, plaintxt.len);
        defer {
            @memcpy(ciphertxt, buf);
            self.allocator.free(buf);
        }

        var c_chr_count: usize = 0;
        for (plaintxt, 0..) |c, i| {
            if (std.ascii.isAlphabetic(c))
            {
                buf[i] = ciphertxt[c_chr_count];
                c_chr_count += 1;
            } else {
                buf[i] = c;
            }
        }
    }
};

fn clear_str(buf: []u8) []u8 {
    var write_idx: usize = 0;
    for (buf) |char| {
        if ((char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z')) {
            buf[write_idx] = char;
            write_idx += 1;
        }
    }
    return buf[0..write_idx];
}

test "Caesar cipher" {
    const C = try Cipher(Caesar).init(.{3});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Khoor Zruog", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Multiplicative cipher" {
    const C = try Cipher(Multiplicative).init(.{3});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Vmhhq Oqzhj", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);

    const C_err = Cipher(Multiplicative).init(.{2});
    try std.testing.expectError(KeyError.InvalidKey, C_err);
}

test "Affine cipher" {
    const C = try Cipher(Affine).init(.{3, 9});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Evqqz Xziqs", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);

    const C_err = Cipher(Multiplicative).init(.{2});
    try std.testing.expectError(KeyError.InvalidKey, C_err);
}

test "Autokey cipher" {
    const C = try Cipher(Autokey).init(.{std.testing.allocator, "N"});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Ulpwz Kkfco", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Viegener cipher" {
    const C = try Cipher(Viegener).init(.{"Cybre"});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Jcmcs Ymsch", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Zigzag cipher" {
    const C = try Cipher(Zigzag).init(.{std.testing.allocator, 4});
    const value = "Hello World";
    var buf = [_]u8{0} ** value.len;

    try C.encrypt(value, &buf);
    try std.testing.expectEqualSlices(u8, "HWeol ordll", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}
