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
                // the '+ 26' is a workaround for the overflow problemoo
                buf[idx] = @mod((c - 'a') + 26 - self.shift, 26) + 'a';
            } else if (c >= 'A' and c <= 'Z') {
                buf[idx] = @mod((c - 'A') + 26 - self.shift, 26) + 'A';
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
            null, 1,  null, 9,  null, 21,   null, 15,
            null, 3,  null, 19, null, null, null, 7,
            null, 23, null, 11, null, 5,    null, 17,
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
            if (!std.ascii.isAlphabetic(c)) {
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
            null, 1,  null, 9,  null, 21,   null, 15,
            null, 3,  null, 19, null, null, null, 7,
            null, 23, null, 11, null, 5,    null, 17,
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
            if (self.key.len > plaintxt.len) self.key.len else plaintxt.len,
        );
        defer self.allocator.free(full_key);

        @memcpy(full_key[0..self.key.len], self.key);
        if (!(plaintxt.len < self.key.len)) {
            @memcpy(full_key[self.key.len..], plaintxt[0..(plaintxt.len - self.key.len)]);
        }

        const cleared_key = clear_str(full_key);

        var key_idx: usize = 0;
        for (plaintxt, 0..) |c, idx| {
            if (!std.ascii.isAlphabetic(c)) {
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

        var key_idx: usize = 0;
        for (ciphertxt, 0..) |c, idx| {
            if (!std.ascii.isAlphabetic(c)) {
                buf[idx] = c;
                continue;
            }

            var key =
                if (key_idx < self.key.len)
                    @as(i16, self.key[key_idx])
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
        var key_idx: usize = 0;
        for (plaintxt, 0..) |c, idx| {
            if (!std.ascii.isAlphabetic(c)) {
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
        var key_idx: usize = 0;
        for (ciphertxt, 0..) |c, idx| {
            if (!std.ascii.isAlphabetic(c)) {
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
        var row_counts = try self.allocator.alloc(usize, self.rails);
        defer self.allocator.free(row_counts);

        @memset(row_counts, 0);

        for (plaintxt, 0..) |c, i| {
            if (!std.ascii.isAlphabetic(c))
                continue;

            row_counts[self.rail_at(i)] += 1;
        }

        var offsets = try self.allocator.alloc(usize, self.rails);
        defer self.allocator.free(offsets);

        offsets[0] = 0;
        for (1..self.rails) |r| {
            offsets[r] = offsets[r - 1] + row_counts[r - 1];
        }

        for (plaintxt, 0..) |c, i| {
            if (!std.ascii.isAlphabetic(c)) {
                continue;
            }

            const rail = self.rail_at(i);
            buf[offsets[rail]] = c;
            offsets[rail] += 1;
        }

        try self.restore_formatting(plaintxt, buf);
    }

    pub fn decrypt(self: Zigzag, ciphertxt: []const u8, buf: []u8) !void {
        const clean_cipher = try self.allocator.alloc(u8, ciphertxt.len);
        defer self.allocator.free(clean_cipher);

        var clean_len: usize = 0;
        for (ciphertxt) |c| {
            if (std.ascii.isAlphabetic(c)) {
                clean_cipher[clean_len] = c;
                clean_len += 1;
            }
        }

        const row_counts = try self.allocator.alloc(usize, self.rails);
        defer self.allocator.free(row_counts);
        @memset(row_counts, 0);

        for (ciphertxt, 0..) |c, i| {
            if (std.ascii.isAlphabetic(c)) {
                row_counts[self.rail_at(i)] += 1;
            }
        }

        const offsets = try self.allocator.alloc(usize, self.rails);
        defer self.allocator.free(offsets);

        offsets[0] = 0;
        for (1..self.rails) |r| {
            offsets[r] = offsets[r - 1] + row_counts[r - 1];
        }

        for (ciphertxt, 0..) |c, i| {
            if (!std.ascii.isAlphabetic(c)) {
                buf[i] = c;
                continue;
            }

            const rail = self.rail_at(i);
            buf[i] = clean_cipher[offsets[rail]];
            offsets[rail] += 1;
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
            if (std.ascii.isAlphabetic(c)) {
                buf[i] = ciphertxt[c_chr_count];
                c_chr_count += 1;
            } else {
                buf[i] = c;
            }
        }
    }
};

pub const Atbash = struct {
    pub fn init() KeyError!Atbash {
        return .{};
    }

    pub fn encrypt(self: Atbash, plaintxt: []const u8, buf: []u8) !void {
        _ = self;
        mirror(plaintxt, buf);
    }

    pub fn decrypt(self: Atbash, ciphertxt: []const u8, buf: []u8) !void {
        _ = self;
        mirror(ciphertxt, buf);
    }
};

pub const Rot13 = struct {
    pub fn init() KeyError!Rot13 {
        return .{};
    }

    pub fn encrypt(self: Rot13, plaintxt: []const u8, buf: []u8) !void {
        _ = self;
        shift13(plaintxt, buf);
    }

    pub fn decrypt(self: Rot13, ciphertxt: []const u8, buf: []u8) !void {
        _ = self;
        shift13(ciphertxt, buf);
    }
};

pub const Beaufort = struct {
    key: []const u8,

    pub fn init(key: []const u8) KeyError!Beaufort {
        if (key.len == 0) return KeyError.NoKeyProvided;
        return .{ .key = key };
    }

    pub fn encrypt(self: Beaufort, plaintxt: []const u8, buf: []u8) !void {
        var key_idx: usize = 0;
        for (plaintxt, 0..) |c, idx| {
            if (!std.ascii.isAlphabetic(c)) {
                buf[idx] = c;
                continue;
            }

            const key_val: i16 = norm_key(self.key[key_idx % self.key.len]);
            const char_val: i16 = c - (if (c >= 'a' and c <= 'z') @as(u8, 'a') else 'A');
            buf[idx] = @intCast(@mod(key_val - char_val, 26) + @as(i16, if (c >= 'a' and c <= 'z') @as(u8, 'a') else 'A'));
            key_idx += 1;
        }
    }

    pub fn decrypt(self: Beaufort, ciphertxt: []const u8, buf: []u8) !void {
        try self.encrypt(ciphertxt, buf);
    }
};

pub const ColumnarTransposition = struct {
    key: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, key: []const u8) KeyError!ColumnarTransposition {
        if (key.len == 0) return KeyError.NoKeyProvided;
        return .{ .key = key, .allocator = allocator };
    }

    pub fn encrypt(self: ColumnarTransposition, plaintxt: []const u8, buf: []u8) !void {
        const letters = try self.allocator.dupe(u8, plaintxt);
        defer self.allocator.free(letters);
        const clean = clear_str(letters);

        const k = self.key.len;
        const n = clean.len;
        const rows = (n + k - 1) / k;
        const full = n % k;

        const order = try self.columnOrder();
        defer self.allocator.free(order);

        const out_letters = try self.allocator.alloc(u8, n);
        defer self.allocator.free(out_letters);

        var w: usize = 0;
        for (order) |c| {
            const height = columnHeight(c, rows, full);
            for (0..height) |r| {
                out_letters[w] = clean[r * k + c];
                w += 1;
            }
        }

        try restore_formatting(self.allocator, plaintxt, buf, out_letters, false);
    }

    pub fn decrypt(self: ColumnarTransposition, ciphertxt: []const u8, buf: []u8) !void {
        const letters = try self.allocator.dupe(u8, ciphertxt);
        defer self.allocator.free(letters);
        const clean = clear_str(letters);

        const k = self.key.len;
        const n = clean.len;
        const rows = (n + k - 1) / k;
        const full = n % k;

        const order = try self.columnOrder();
        defer self.allocator.free(order);

        const grid = try self.allocator.alloc(u8, rows * k);
        defer self.allocator.free(grid);

        var r: usize = 0;
        for (order) |c| {
            const height = columnHeight(c, rows, full);
            for (0..height) |row| {
                grid[row * k + c] = clean[r];
                r += 1;
            }
        }

        const out_letters = try self.allocator.alloc(u8, n);
        defer self.allocator.free(out_letters);
        for (0..n) |i| {
            out_letters[i] = grid[i];
        }

        try restore_formatting(self.allocator, ciphertxt, buf, out_letters, false);
    }

    fn columnOrder(self: ColumnarTransposition) ![]usize {
        const order = try self.allocator.alloc(usize, self.key.len);
        errdefer self.allocator.free(order);

        for (0..self.key.len) |i| {
            order[i] = i;
        }

        for (1..self.key.len) |i| {
            const cur = order[i];
            var j = i;
            while (j > 0 and norm_key(self.key[order[j - 1]]) > norm_key(self.key[cur])) : (j -= 1) {
                order[j] = order[j - 1];
            }
            order[j] = cur;
        }
        return order;
    }
};

fn columnHeight(c: usize, rows: usize, full: usize) usize {
    if (full == 0) return rows;
    return if (c < full) rows else rows - 1;
}

pub const Bifid = struct {
    key: []const u8,
    allocator: std.mem.Allocator,
    square: [25]u8,

    pub fn init(allocator: std.mem.Allocator, key: []const u8) KeyError!Bifid {
        if (key.len == 0) return KeyError.NoKeyProvided;
        return .{ .key = key, .allocator = allocator, .square = buildSquare(key) };
    }

    pub fn encrypt(self: Bifid, plaintxt: []const u8, buf: []u8) !void {
        const letters = try self.allocator.dupe(u8, plaintxt);
        defer self.allocator.free(letters);
        const clean = clear_str(letters);
        const n = clean.len;

        const seq = try self.allocator.alloc(u8, 2 * n);
        defer self.allocator.free(seq);

        for (clean, 0..) |c, i| {
            const idx = self.coords(c);
            seq[i] = @intCast(idx / 5);
            seq[n + i] = @intCast(idx % 5);
        }

        const out_letters = try self.allocator.alloc(u8, n);
        defer self.allocator.free(out_letters);
        for (0..n) |i| {
            out_letters[i] = self.square[seq[2 * i] * 5 + seq[2 * i + 1]];
        }

        try restore_formatting(self.allocator, plaintxt, buf, out_letters, true);
    }

    pub fn decrypt(self: Bifid, ciphertxt: []const u8, buf: []u8) !void {
        const letters = try self.allocator.dupe(u8, ciphertxt);
        defer self.allocator.free(letters);
        const clean = clear_str(letters);
        const n = clean.len;

        const seq = try self.allocator.alloc(u8, 2 * n);
        defer self.allocator.free(seq);

        for (clean, 0..) |c, i| {
            const idx = self.coords(c);
            seq[2 * i] = @intCast(idx / 5);
            seq[2 * i + 1] = @intCast(idx % 5);
        }

        const out_letters = try self.allocator.alloc(u8, n);
        defer self.allocator.free(out_letters);
        for (0..n) |i| {
            out_letters[i] = self.square[seq[i] * 5 + seq[n + i]];
        }

        try restore_formatting(self.allocator, ciphertxt, buf, out_letters, true);
    }

    fn coords(self: Bifid, c: u8) usize {
        const target = if (c == 'J' or c == 'j') 'i' else std.ascii.toLower(c);
        for (self.square, 0..) |ch, i| {
            if (ch == target) return i;
        }
        unreachable;
    }
};

fn buildSquare(key: []const u8) [25]u8 {
    var square: [25]u8 = undefined;
    var used: [26]bool = [_]bool{false} ** 26;
    var w: usize = 0;

    for (key) |c| {
        if (!std.ascii.isAlphabetic(c)) continue;
        const t = std.ascii.toLower(c);
        if (t == 'j') continue;
        const idx = t - 'a';
        if (used[idx]) continue;
        used[idx] = true;
        square[w] = t;
        w += 1;
    }

    for (0..26) |i| {
        const ch: u8 = 'a' + @as(u8, @intCast(i));
        if (ch == 'j' or used[i]) continue;
        square[w] = ch;
        w += 1;
    }
    return square;
}

fn mirror(text: []const u8, buf: []u8) void {
    for (text, 0..) |c, idx| {
        if (c >= 'a' and c <= 'z') {
            buf[idx] = 'z' - (c - 'a');
        } else if (c >= 'A' and c <= 'Z') {
            buf[idx] = 'Z' - (c - 'A');
        } else {
            buf[idx] = c;
        }
    }
}

fn shift13(text: []const u8, buf: []u8) void {
    for (text, 0..) |c, idx| {
        if (c >= 'a' and c <= 'z') {
            buf[idx] = @mod((c - 'a') + 13, 26) + 'a';
        } else if (c >= 'A' and c <= 'Z') {
            buf[idx] = @mod((c - 'A') + 13, 26) + 'A';
        } else {
            buf[idx] = c;
        }
    }
}

fn norm_key(c: u8) i16 {
    return @intCast(if (c >= 'a' and c <= 'z') c - 'a' else c - 'A');
}

fn restore_formatting(
    allocator: std.mem.Allocator,
    original: []const u8,
    output: []u8,
    letters: []const u8,
    preserve_case: bool,
) !void {
    const buf = try allocator.alloc(u8, original.len);
    defer allocator.free(buf);

    var c_chr_count: usize = 0;
    for (original, 0..) |c, i| {
        if (std.ascii.isAlphabetic(c)) {
            var ch = letters[c_chr_count];
            if (preserve_case and std.ascii.isUpper(c)) ch = std.ascii.toUpper(ch);
            buf[i] = ch;
            c_chr_count += 1;
        } else {
            buf[i] = c;
        }
    }
    @memcpy(output, buf);
}

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
    const C = try Cipher(Affine).init(.{ 3, 9 });
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Evqqz Xziqs", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);

    const C_err = Cipher(Multiplicative).init(.{2});
    try std.testing.expectError(KeyError.InvalidKey, C_err);
}

test "Autokey cipher" {
    const C = try Cipher(Autokey).init(.{ std.testing.allocator, "N" });
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
    const C = try Cipher(Zigzag).init(.{ std.testing.allocator, 4 });
    const value = "Hello World";
    var buf = [_]u8{0} ** value.len;

    try C.encrypt(value, &buf);
    try std.testing.expectEqualSlices(u8, "HWeol ordll", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Atbash cipher" {
    const C = try Cipher(Atbash).init(.{});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Svool Dliow", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Rot13 cipher" {
    const C = try Cipher(Rot13).init(.{});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Uryyb Jbeyq", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Beaufort cipher" {
    const C = try Cipher(Beaufort).init(.{"Cybre"});
    var buf = [_]u8{0} ** 11;

    try C.encrypt("Hello World", &buf);
    try std.testing.expectEqualSlices(u8, "Vuqgq Gkkgb", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);

    const C_err = Cipher(Beaufort).init(.{""});
    try std.testing.expectError(KeyError.NoKeyProvided, C_err);
}

test "Columnar Transposition cipher" {
    const C = try Cipher(ColumnarTransposition).init(.{ std.testing.allocator, "zebra" });
    const value = "Hello World";
    var buf = [_]u8{0} ** value.len;

    try C.encrypt(value, &buf);
    try std.testing.expectEqualSlices(u8, "odlre ollHW", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

test "Bifid cipher" {
    const C = try Cipher(Bifid).init(.{ std.testing.allocator, "keyword" });
    const value = "Hello World";
    var buf = [_]u8{0} ** value.len;

    try C.encrypt(value, &buf);
    try std.testing.expectEqualSlices(u8, "Fhkeg Gzxtu", &buf);

    try C.decrypt(&buf, &buf);
    try std.testing.expectEqualSlices(u8, "Hello World", &buf);
}

/// DES (Data Encryption Standard) in ECB mode, hand-written per FIPS 46-3.
/// 8-byte key, 64-bit blocks, PKCS#7 padding. Educational implementation.
pub const DesEcb = struct {
    key: [8]u8,

    const block_bits: usize = 64;
    const block_bytes: usize = 8;

    const ip_table = [_]u8{
        58, 50, 42, 34, 26, 18, 10, 2,
        60, 52, 44, 36, 28, 20, 12, 4,
        62, 54, 46, 38, 30, 22, 14, 6,
        64, 56, 48, 40, 32, 24, 16, 8,
        57, 49, 41, 33, 25, 17, 9,  1,
        59, 51, 43, 35, 27, 19, 11, 3,
        61, 53, 45, 37, 29, 21, 13, 5,
        63, 55, 47, 39, 31, 23, 15, 7,
    };
    const fp_table = [_]u8{
        40, 8,  48, 16, 56, 24, 64, 32,
        39, 7,  47, 15, 55, 23, 63, 31,
        38, 6,  46, 14, 54, 22, 62, 30,
        37, 5,  45, 13, 53, 21, 61, 29,
        36, 4,  44, 12, 52, 20, 60, 28,
        35, 3,  43, 11, 51, 19, 59, 27,
        34, 2,  42, 10, 50, 18, 58, 26,
        33, 1,  41, 9,  49, 17, 57, 25,
    };
    const pc1_table = [_]u8{
        57, 49, 41, 33, 25, 17, 9,
        1,  58, 50, 42, 34, 26, 18,
        10, 2,  59, 51, 43, 35, 27,
        19, 11, 3,  60, 52, 44, 36,
        63, 55, 47, 39, 31, 23, 15,
        7,  62, 54, 46, 38, 30, 22,
        14, 6,  61, 53, 45, 37, 29,
        21, 13, 5,  28, 20, 12, 4,
    };
    const pc2_table = [_]u8{
        14, 17, 11, 24, 1,  5,
        3,  28, 15, 6,  21, 10,
        23, 19, 12, 4,  26, 8,
        16, 7,  27, 20, 13, 2,
        41, 52, 31, 37, 47, 55,
        30, 40, 51, 45, 33, 48,
        44, 49, 39, 56, 34, 53,
        46, 42, 50, 36, 29, 32,
    };
    const shifts = [_]u8{ 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1 };
    const expansion_table = [_]u8{
        32, 1,  2,  3,  4,  5,
        4,  5,  6,  7,  8,  9,
        8,  9,  10, 11, 12, 13,
        12, 13, 14, 15, 16, 17,
        16, 17, 18, 19, 20, 21,
        20, 21, 22, 23, 24, 25,
        24, 25, 26, 27, 28, 29,
        28, 29, 30, 31, 32, 1,
    };
    const sbox = [_][4][16]u8{
        .{
            .{ 14, 4,  13, 1,  2,  15, 11, 8,  3,  10, 6,  12, 5,  9,  0,  7 },
            .{ 0,  15, 7,  4,  14, 2,  13, 1,  10, 6,  12, 11, 9,  5,  3,  8 },
            .{ 4,  1,  14, 8,  13, 6,  2,  11, 15, 12, 9,  7,  3,  10, 5,  0 },
            .{ 15, 12, 8,  2,  4,  9,  1,  7,  5,  11, 3,  14, 10, 0,  6,  13 },
        },
        .{
            .{ 15, 1,  8,  14, 6,  11, 3,  4,  9,  7,  2,  13, 12, 0,  5,  10 },
            .{ 3,  13, 4,  7,  15, 2,  8,  14, 12, 0,  1,  10, 6,  9,  11, 5 },
            .{ 0,  14, 7,  11, 10, 4,  13, 1,  5,  8,  12, 6,  9,  3,  2,  15 },
            .{ 13, 8,  10, 1,  3,  15, 4,  2,  11, 6,  7,  12, 0,  5,  14, 9 },
        },
        .{
            .{ 10, 0,  9,  14, 6,  3,  15, 5,  1,  13, 12, 7,  11, 4,  2,  8 },
            .{ 13, 7,  0,  9,  3,  4,  6,  10, 2,  8,  5,  14, 12, 11, 15, 1 },
            .{ 13, 6,  4,  9,  8,  15, 3,  0,  11, 1,  2,  12, 5,  10, 14, 7 },
            .{ 1,  10, 13, 0,  6,  9,  8,  7,  4,  15, 14, 3,  11, 5,  2,  12 },
        },
        .{
            .{ 7,  13, 14, 3,  0,  6,  9,  10, 1,  2,  8,  5,  11, 12, 4,  15 },
            .{ 13, 8,  11, 5,  6,  15, 0,  3,  4,  7,  2,  12, 1,  10, 14, 9 },
            .{ 10, 6,  9,  0,  12, 11, 7,  13, 15, 1,  3,  14, 5,  2,  8,  4 },
            .{ 3,  15, 0,  6,  10, 1,  13, 8,  9,  4,  5,  11, 12, 7,  2,  14 },
        },
        .{
            .{ 2,  12, 4,  1,  7,  10, 11, 6,  8,  5,  3,  15, 13, 0,  14, 9 },
            .{ 14, 11, 2,  12, 4,  7,  13, 1,  5,  0,  15, 10, 3,  9,  8,  6 },
            .{ 4,  2,  1,  11, 10, 13, 7,  8,  15, 9,  12, 5,  6,  3,  0,  14 },
            .{ 11, 8,  12, 7,  1,  14, 2,  13, 6,  15, 0,  9,  10, 4,  5,  3 },
        },
        .{
            .{ 12, 1,  10, 15, 9,  2,  6,  8,  0,  13, 3,  4,  14, 7,  5,  11 },
            .{ 10, 15, 4,  2,  7,  12, 9,  5,  6,  1,  13, 14, 0,  11, 3,  8 },
            .{ 9,  14, 15, 5,  2,  8,  12, 3,  7,  0,  4,  10, 1,  13, 11, 6 },
            .{ 4,  3,  2,  12, 9,  5,  15, 10, 11, 14, 1,  7,  6,  0,  8,  13 },
        },
        .{
            .{ 4,  11, 2,  14, 15, 0,  8,  13, 3,  12, 9,  7,  5,  10, 6,  1 },
            .{ 13, 0,  11, 7,  4,  9,  1,  10, 14, 3,  5,  12, 2,  15, 8,  6 },
            .{ 1,  4,  11, 13, 12, 3,  7,  14, 10, 15, 6,  8,  0,  5,  9,  2 },
            .{ 6,  11, 13, 8,  1,  4,  10, 7,  9,  5,  0,  15, 14, 2,  3,  12 },
        },
        .{
            .{ 13, 2,  8,  4,  6,  15, 11, 1,  10, 9,  3,  14, 5,  0,  12, 7 },
            .{ 1,  15, 13, 8,  10, 3,  7,  4,  12, 5,  6,  11, 0,  14, 9,  2 },
            .{ 7,  11, 4,  1,  9,  12, 14, 2,  0,  6,  10, 13, 15, 3,  5,  8 },
            .{ 2,  1,  14, 7,  4,  10, 8,  13, 15, 12, 9,  0,  3,  5,  6,  11 },
        },
    };
    const p_table = [_]u8{
        16, 7,  20, 21,
        29, 12, 28, 17,
        1,  15, 23, 26,
        5,  18, 31, 10,
        2,  8,  24, 14,
        32, 27, 3,  9,
        19, 13, 30, 6,
        22, 11, 4,  25,
    };

    pub fn init(key: []const u8) KeyError!DesEcb {
        if (key.len == 0) return KeyError.NoKeyProvided;
        if (key.len != 8) return KeyError.InvalidKey;
        var k: [8]u8 = undefined;
        @memcpy(&k, key[0..8]);
        return .{ .key = k };
    }

    pub fn encrypt(self: DesEcb, plaintext: []const u8, buf: []u8) !void {
        const padded_len = padLen(plaintext.len);
        if (buf.len < padded_len) return error.BufferTooSmall;
        const total_blocks = padded_len / block_bytes;

        const keys1 = self.keySchedule(false);

        var i: usize = 0;
        while (i < total_blocks) : (i += 1) {
            var block: [8]u8 = undefined;
            const src_off = i * block_bytes;
            const copy_len = if (plaintext.len >= src_off + 8) 8 else plaintext.len - src_off;
            @memset(&block, 0);
            @memcpy(block[0..copy_len], plaintext[src_off..][0..copy_len]);
            if (i == total_blocks - 1) {
                padBlock(&block, plaintext.len % 8);
            }
            encryptBlock(&block, &keys1);
            @memcpy(buf[src_off..][0..8], &block);
        }
    }

    pub fn decrypt(self: DesEcb, ciphertext: []const u8, buf: []u8) !void {
        if (ciphertext.len % block_bytes != 0) return error.InvalidCiphertext;
        if (buf.len < ciphertext.len) return error.BufferTooSmall;
        const total_blocks = ciphertext.len / block_bytes;
        const keys1 = self.keySchedule(true);

        var i: usize = 0;
        while (i < total_blocks) : (i += 1) {
            const off = i * block_bytes;
            var block: [8]u8 = undefined;
            @memcpy(&block, ciphertext[off..][0..8]);
            decryptBlock(&block, &keys1);
            if (i == total_blocks - 1) {
                _ = unpad(&block) catch return error.InvalidCiphertext;
            }
            @memcpy(buf[off..][0..8], &block);
        }
    }

    fn keySchedule(self: DesEcb, reverse: bool) [16][8]u8 {
        var k64_bits: [64]bool = undefined;
        for (0..64) |i| {
            k64_bits[i] = getBit(&self.key, i);
        }
        var c: [56]bool = undefined;
        var d: [56]bool = undefined;
        for (0..28) |i| {
            c[i] = k64_bits[pc1_table[i] - 1];
            d[i] = k64_bits[pc1_table[28 + i] - 1];
        }

        var keys: [16][8]u8 = undefined;
        for (0..16) |round| {
            const sh = shifts[round];
            rotateLeft(&c, 28, sh);
            rotateLeft(&d, 28, sh);
            var k56: [56]bool = undefined;
            @memcpy(k56[0..28], c[0..28]);
            @memcpy(k56[28..56], d[0..28]);
            keys[round] = permutePc2(&k56);
        }
        if (reverse) {
            var j: usize = 0;
            while (j < 8) : (j += 1) {
                const tmp = keys[j];
                keys[j] = keys[15 - j];
                keys[15 - j] = tmp;
            }
        }
        return keys;
    }

    fn encryptBlock(block: *[8]u8, keys: *const [16][8]u8) void {
        var bits: [64]bool = undefined;
        for (0..64) |i| bits[i] = getBit(block, ip_table[i] - 1);

        var l: [32]bool = undefined;
        var r: [32]bool = undefined;
        @memcpy(l[0..32], bits[0..32]);
        @memcpy(r[0..32], bits[32..64]);

        for (0..16) |round| {
            const f = fFunc(r, &keys[round]);
            var new_l: [32]bool = undefined;
            for (0..32) |i| new_l[i] = r[i];
            for (0..32) |i| r[i] = l[i] ^ f[i];
            @memcpy(&l, &new_l);
        }

        var pre: [64]bool = undefined;
        @memcpy(pre[0..32], &r);
        @memcpy(pre[32..64], &l);
        for (0..64) |i| bits[i] = pre[fp_table[i] - 1];
        setBits(block, &bits);
    }

    fn decryptBlock(block: *[8]u8, keys: *const [16][8]u8) void {
        // decrypt uses same structure with reversed subkeys (handled in keySchedule())
        encryptBlock(block, keys);
    }

    fn fFunc(r: [32]bool, sk: *const [8]u8) [32]bool {
        var exp: [48]bool = undefined;
        for (0..48) |i| exp[i] = r[expansion_table[i] - 1];
        var sk_bits: [48]bool = undefined;
        for (0..48) |i| sk_bits[i] = getBit(sk, i);
        var x: [48]bool = undefined;
        for (0..48) |i| x[i] = exp[i] ^ sk_bits[i];

        var combined: [32]bool = undefined;
        for (0..8) |s| {
            const slice = x[s * 6 .. s * 6 + 6];
            const b0: u4 = if (slice[0]) 1 else 0;
            const b1: u4 = if (slice[1]) 1 else 0;
            const b2: u4 = if (slice[2]) 1 else 0;
            const b3: u4 = if (slice[3]) 1 else 0;
            const b4: u4 = if (slice[4]) 1 else 0;
            const b5: u4 = if (slice[5]) 1 else 0;
            const row = (b0 << 1) | b5;
            const col = (b1 << 3) | (b2 << 2) | (b3 << 1) | b4;
            const val = sbox[s][@as(usize, row)][@as(usize, col)];
            for (0..4) |b| {
                combined[s * 4 + b] = (val >> @intCast(3 - b)) & 1 == 1;
            }
        }
        var out: [32]bool = undefined;
        for (0..32) |i| out[i] = combined[p_table[i] - 1];
        return out;
    }

    fn permutePc2(k56: *const [56]bool) [8]u8 {
        var bits: [48]bool = undefined;
        for (0..48) |i| bits[i] = k56.*[pc2_table[i] - 1];
        var out: [48]u8 = undefined;
        for (0..48) |i| out[i] = if (bits[i]) 1 else 0;
        var bytes: [8]u8 = undefined;
        bitsToBytes(&out, &bytes);
        return bytes;
    }
};

fn padLen(len: usize) usize {
    const rem = len % 8;
    return if (rem == 0) len + 8 else len + (8 - rem);
}

fn padBlock(block: *[8]u8, used: usize) void {
    const rem = used % 8;
    const pad = if (rem == 0) 8 else (8 - rem);
    for (rem..8) |i| block.*[i] = @intCast(pad);
}

fn unpad(block: *const [8]u8) !usize {
    const pad: usize = block.*[7];
    if (pad == 0 or pad > 8) return error.InvalidCiphertext;
    for (7 - (pad - 1)..8) |i| {
        if (block.*[i] != pad) return error.InvalidCiphertext;
    }
    return pad;
}

fn getBit(bytes: *const [8]u8, bit: usize) bool {
    const byte = bit / 8;
    const off = 7 - (bit % 8);
    return (bytes.*[byte] >> @intCast(off)) & 1 == 1;
}

fn setBits(bytes: *[8]u8, bits: *const [64]bool) void {
    for (0..64) |i| {
        const byte = i / 8;
        const off: u3 = @intCast(7 - (i % 8));
        bytes.*[byte] = (bytes.*[byte] & ~(@as(u8, 1) << off)) | (@as(u8, if (bits[i]) 1 else 0) << off);
    }
}

fn bitsToBytes(bits: *[48]u8, bytes: *[8]u8) void {
    for (0..48) |i| {
        const byte = i / 8;
        const off: u3 = @intCast(7 - (i % 8));
        bytes.*[byte] = (bytes.*[byte] & ~(@as(u8, 1) << off)) | (bits[i] << off);
    }
}

fn rotateLeft(bits: *[56]bool, len: usize, shifts: u8) void {
    const sh: usize = shifts;
    var tmp: [56]bool = undefined;
    @memcpy(tmp[0..len], bits[0..len]);
    for (0..len) |i| bits.*[i] = tmp[(i + sh) % len];
}

test "DES NIST known-answer test" {
    // FIPS 46-3 / classic known answer:
    // key = 133457799BBCDFF1 (raw 8 bytes), plaintext = 0123456789ABCDEF
    // ciphertext = 85E813540F0AB405
    const key = [_]u8{ 0x13, 0x34, 0x57, 0x79, 0x9B, 0xBC, 0xDF, 0xF1 };
    const C = try Cipher(DesEcb).init(.{&key});
    const plain = [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF };
    var enc: [24]u8 = undefined;
    try C.encrypt(&plain, &enc);
    const expected = [_]u8{ 0x85, 0xE8, 0x13, 0x54, 0x0F, 0x0A, 0xB4, 0x05 };
    try std.testing.expectEqualSlices(u8, &expected, enc[0..8]);
}

test "DES ECB round trip" {
    const C = try Cipher(DesEcb).init(.{"abcdefgh"});
    const cases = [_][]const u8{
        "hello",
        "",
        "a",
        "12345678",
        "1234567890",
        "The quick brown fox jumps over the lazy dog 0123456789",
    };
    for (cases) |msg| {
        const enc_len = if (msg.len % 8 == 0) msg.len + 8 else msg.len + (8 - msg.len % 8);
        const enc = try std.testing.allocator.alloc(u8, enc_len);
        defer std.testing.allocator.free(enc);
        try C.encrypt(msg, enc);

        const dec = try std.testing.allocator.alloc(u8, msg.len + 8);
        defer std.testing.allocator.free(dec);
        try C.decrypt(enc, dec);
        try std.testing.expectEqualSlices(u8, msg, dec[0..msg.len]);
    }
}

test "DES requires 8-byte key" {
    try std.testing.expectError(KeyError.NoKeyProvided, DesEcb.init(""));
    try std.testing.expectError(KeyError.InvalidKey, DesEcb.init("short"));
    _ = try DesEcb.init("12345678");
}
