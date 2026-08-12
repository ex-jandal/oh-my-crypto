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
