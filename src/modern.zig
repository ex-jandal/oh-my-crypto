const std = @import("std");

const crypto = std.crypto;
const mem = std.mem;

const version: u8 = 1;
const magic = "OMC2";
const salt_length: usize = 16;
const tag_length: usize = 16;
const key_length: usize = 32;

pub const Kdf = enum(u8) {
    argon2id,
    pbkdf2_sha256,
    scrypt,
};

pub const Aead = enum(u8) {
    xchacha20_poly1305,
    chacha20_poly1305,
    aes256_gcm,
    aes128_gcm,
    aes256_gcm_siv,
    aes128_gcm_siv,
    aegis256,
    aegis128l,
    xsalsa20_poly1305,
    xchacha12_poly1305,
    chacha12_poly1305,

    pub fn nonceLength(self: Aead) usize {
        return switch (self) {
            .xchacha20_poly1305 => crypto.aead.chacha_poly.XChaCha20Poly1305.nonce_length,
            .chacha20_poly1305 => crypto.aead.chacha_poly.ChaCha20Poly1305.nonce_length,
            .xchacha12_poly1305 => crypto.aead.chacha_poly.XChaCha12Poly1305.nonce_length,
            .chacha12_poly1305 => crypto.aead.chacha_poly.ChaCha12Poly1305.nonce_length,
            .aes256_gcm => crypto.aead.aes_gcm.Aes256Gcm.nonce_length,
            .aes128_gcm => crypto.aead.aes_gcm.Aes128Gcm.nonce_length,
            .aes256_gcm_siv => crypto.aead.aes_gcm_siv.Aes256GcmSiv.nonce_length,
            .aes128_gcm_siv => crypto.aead.aes_gcm_siv.Aes128GcmSiv.nonce_length,
            .aegis256 => crypto.aead.aegis.Aegis256.nonce_length,
            .aegis128l => crypto.aead.aegis.Aegis128L.nonce_length,
            .xsalsa20_poly1305 => crypto.aead.salsa_poly.XSalsa20Poly1305.nonce_length,
        };
    }

    pub fn keyLength(self: Aead) usize {
        return switch (self) {
            .xchacha20_poly1305 => crypto.aead.chacha_poly.XChaCha20Poly1305.key_length,
            .chacha20_poly1305 => crypto.aead.chacha_poly.ChaCha20Poly1305.key_length,
            .xchacha12_poly1305 => crypto.aead.chacha_poly.XChaCha12Poly1305.key_length,
            .chacha12_poly1305 => crypto.aead.chacha_poly.ChaCha12Poly1305.key_length,
            .aes256_gcm => crypto.aead.aes_gcm.Aes256Gcm.key_length,
            .aes128_gcm => crypto.aead.aes_gcm.Aes128Gcm.key_length,
            .aes256_gcm_siv => crypto.aead.aes_gcm_siv.Aes256GcmSiv.key_length,
            .aes128_gcm_siv => crypto.aead.aes_gcm_siv.Aes128GcmSiv.key_length,
            .aegis256 => crypto.aead.aegis.Aegis256.key_length,
            .aegis128l => crypto.aead.aegis.Aegis128L.key_length,
            .xsalsa20_poly1305 => crypto.aead.salsa_poly.XSalsa20Poly1305.key_length,
        };
    }
};

pub const HashAlgo = enum {
    sha256,
    sha512,
    sha3_256,
    blake3,
    sha1,
    md5,
    sha224,
    sha384,
    sha512_256,
    sha3_224,
    sha3_384,
    sha3_512,
    shake128,
    shake256,
    blake2s256,
    blake2b512,
};

pub const Argon2Params = struct {
    m: u32,
    t: u32,
    p: u24,
};

pub const Pbkdf2Params = struct {
    rounds: u32,
};

pub const ScryptParams = struct {
    ln: u6,
    r: u30,
    p: u30,
};

pub const KdfParams = union(Kdf) {
    argon2id: Argon2Params,
    pbkdf2_sha256: Pbkdf2Params,
    scrypt: ScryptParams,
};

pub const EncryptOptions = struct {
    kdf: Kdf = .argon2id,
    aead: Aead = .xchacha20_poly1305,
    kdf_params: ?KdfParams = null,
};

const ParseError = error{
    InvalidMagic,
    UnsupportedVersion,
    UnsupportedKdf,
    UnsupportedAead,
    InvalidFormat,
};

pub fn encrypt(
    io: std.Io,
    gpa: mem.Allocator,
    password: []const u8,
    plaintext: []const u8,
    opts: EncryptOptions,
) ![]u8 {
    const kdf_params = opts.kdf_params orelse defaultParams(opts.kdf);

    const nonce_len = opts.aead.nonceLength();
    const header_len: usize = 36 + nonce_len;
    const container_len = header_len + tag_length + plaintext.len;

    const container = try gpa.alloc(u8, container_len);
    defer gpa.free(container);

    writeHeader(container, opts.kdf, opts.aead, kdf_params);
    const salt = container[20..36];
    const nonce = container[36..header_len];

    io.random(salt);
    io.random(nonce);

    const key = try deriveKey(io, gpa, opts.kdf, kdf_params, password, salt, key_length);
    defer {
        crypto.secureZero(u8, key);
        gpa.free(key);
    }

    const tag = container[header_len..][0..tag_length];
    const ct = container[header_len + tag_length ..];

    switch (opts.aead) {
        .xchacha20_poly1305 => crypto.aead.chacha_poly.XChaCha20Poly1305.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.chacha_poly.XChaCha20Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.XChaCha20Poly1305.key_length].*,
        ),
        .chacha20_poly1305 => crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.chacha_poly.ChaCha20Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.ChaCha20Poly1305.key_length].*,
        ),
        .xchacha12_poly1305 => crypto.aead.chacha_poly.XChaCha12Poly1305.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.chacha_poly.XChaCha12Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.XChaCha12Poly1305.key_length].*,
        ),
        .chacha12_poly1305 => crypto.aead.chacha_poly.ChaCha12Poly1305.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.chacha_poly.ChaCha12Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.ChaCha12Poly1305.key_length].*,
        ),
        .aes256_gcm => crypto.aead.aes_gcm.Aes256Gcm.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.aes_gcm.Aes256Gcm.nonce_length].*,
            key[0..crypto.aead.aes_gcm.Aes256Gcm.key_length].*,
        ),
        .aes128_gcm => crypto.aead.aes_gcm.Aes128Gcm.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.aes_gcm.Aes128Gcm.nonce_length].*,
            key[0..crypto.aead.aes_gcm.Aes128Gcm.key_length].*,
        ),
        .aes256_gcm_siv => crypto.aead.aes_gcm_siv.Aes256GcmSiv.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.aes_gcm_siv.Aes256GcmSiv.nonce_length].*,
            key[0..crypto.aead.aes_gcm_siv.Aes256GcmSiv.key_length].*,
        ),
        .aes128_gcm_siv => crypto.aead.aes_gcm_siv.Aes128GcmSiv.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.aes_gcm_siv.Aes128GcmSiv.nonce_length].*,
            key[0..crypto.aead.aes_gcm_siv.Aes128GcmSiv.key_length].*,
        ),
        .aegis256 => crypto.aead.aegis.Aegis256.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.aegis.Aegis256.nonce_length].*,
            key[0..crypto.aead.aegis.Aegis256.key_length].*,
        ),
        .aegis128l => crypto.aead.aegis.Aegis128L.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.aegis.Aegis128L.nonce_length].*,
            key[0..crypto.aead.aegis.Aegis128L.key_length].*,
        ),
        .xsalsa20_poly1305 => crypto.aead.salsa_poly.XSalsa20Poly1305.encrypt(
            ct,
            tag,
            plaintext,
            "",
            nonce[0..crypto.aead.salsa_poly.XSalsa20Poly1305.nonce_length].*,
            key[0..crypto.aead.salsa_poly.XSalsa20Poly1305.key_length].*,
        ),
    }

    const out = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(container.len));
    _ = std.base64.standard.Encoder.encode(out, container);
    return out;
}

pub fn decrypt(
    io: std.Io,
    gpa: mem.Allocator,
    password: []const u8,
    encoded: []const u8,
) ![]u8 {
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
    const bin = try gpa.alloc(u8, decoded_len);
    defer gpa.free(bin);
    try std.base64.standard.Decoder.decode(bin, encoded);

    if (bin.len < 4 or !mem.eql(u8, bin[0..4], magic)) return ParseError.InvalidMagic;
    if (bin[4] != version) return ParseError.UnsupportedVersion;
    const kdf = parseKdf(bin[5]) orelse return ParseError.UnsupportedKdf;
    const aead = parseAead(bin[6]) orelse return ParseError.UnsupportedAead;

    const cost1 = mem.readInt(u32, bin[8..12], .little);
    const cost2 = mem.readInt(u32, bin[12..16], .little);
    const cost3 = mem.readInt(u32, bin[16..20], .little);
    const kdf_params = paramsFromCosts(kdf, cost1, cost2, cost3);

    const nonce_len = aead.nonceLength();
    const header_len: usize = 36 + nonce_len;
    if (bin.len < header_len + tag_length) return ParseError.InvalidFormat;

    const salt = bin[20..36];
    const nonce = bin[36..header_len];
    const tag = bin[header_len..][0..tag_length];
    const ct = bin[header_len + tag_length ..];

    const key = try deriveKey(io, gpa, kdf, kdf_params, password, salt, key_length);
    defer {
        crypto.secureZero(u8, key);
        gpa.free(key);
    }

    const pt = try gpa.alloc(u8, ct.len);
    errdefer gpa.free(pt);

    switch (aead) {
        .xchacha20_poly1305 => try crypto.aead.chacha_poly.XChaCha20Poly1305.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.chacha_poly.XChaCha20Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.XChaCha20Poly1305.key_length].*,
        ),
        .chacha20_poly1305 => try crypto.aead.chacha_poly.ChaCha20Poly1305.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.chacha_poly.ChaCha20Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.ChaCha20Poly1305.key_length].*,
        ),
        .xchacha12_poly1305 => try crypto.aead.chacha_poly.XChaCha12Poly1305.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.chacha_poly.XChaCha12Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.XChaCha12Poly1305.key_length].*,
        ),
        .chacha12_poly1305 => try crypto.aead.chacha_poly.ChaCha12Poly1305.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.chacha_poly.ChaCha12Poly1305.nonce_length].*,
            key[0..crypto.aead.chacha_poly.ChaCha12Poly1305.key_length].*,
        ),
        .aes256_gcm => try crypto.aead.aes_gcm.Aes256Gcm.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.aes_gcm.Aes256Gcm.nonce_length].*,
            key[0..crypto.aead.aes_gcm.Aes256Gcm.key_length].*,
        ),
        .aes128_gcm => try crypto.aead.aes_gcm.Aes128Gcm.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.aes_gcm.Aes128Gcm.nonce_length].*,
            key[0..crypto.aead.aes_gcm.Aes128Gcm.key_length].*,
        ),
        .aes256_gcm_siv => try crypto.aead.aes_gcm_siv.Aes256GcmSiv.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.aes_gcm_siv.Aes256GcmSiv.nonce_length].*,
            key[0..crypto.aead.aes_gcm_siv.Aes256GcmSiv.key_length].*,
        ),
        .aes128_gcm_siv => try crypto.aead.aes_gcm_siv.Aes128GcmSiv.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.aes_gcm_siv.Aes128GcmSiv.nonce_length].*,
            key[0..crypto.aead.aes_gcm_siv.Aes128GcmSiv.key_length].*,
        ),
        .aegis256 => try crypto.aead.aegis.Aegis256.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.aegis.Aegis256.nonce_length].*,
            key[0..crypto.aead.aegis.Aegis256.key_length].*,
        ),
        .aegis128l => try crypto.aead.aegis.Aegis128L.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.aegis.Aegis128L.nonce_length].*,
            key[0..crypto.aead.aegis.Aegis128L.key_length].*,
        ),
        .xsalsa20_poly1305 => try crypto.aead.salsa_poly.XSalsa20Poly1305.decrypt(
            pt,
            ct,
            tag.*,
            "",
            nonce[0..crypto.aead.salsa_poly.XSalsa20Poly1305.nonce_length].*,
            key[0..crypto.aead.salsa_poly.XSalsa20Poly1305.key_length].*,
        ),
    }

    return pt;
}

pub fn hash(gpa: mem.Allocator, algo: HashAlgo, data: []const u8) ![]u8 {
    var digest: [64]u8 = undefined;
    const digest_len: usize = switch (algo) {
        .sha256 => blk: {
            crypto.hash.sha2.Sha256.hash(data, digest[0..32], .{});
            break :blk 32;
        },
        .sha512 => blk: {
            crypto.hash.sha2.Sha512.hash(data, digest[0..64], .{});
            break :blk 64;
        },
        .sha3_256 => blk: {
            crypto.hash.sha3.Sha3_256.hash(data, digest[0..32], .{});
            break :blk 32;
        },
        .blake3 => blk: {
            crypto.hash.Blake3.hash(data, digest[0..32], .{});
            break :blk 32;
        },
        .sha1 => blk: {
            crypto.hash.Sha1.hash(data, digest[0..20], .{});
            break :blk 20;
        },
        .md5 => blk: {
            crypto.hash.Md5.hash(data, digest[0..16], .{});
            break :blk 16;
        },
        .sha224 => blk: {
            crypto.hash.sha2.Sha224.hash(data, digest[0..28], .{});
            break :blk 28;
        },
        .sha384 => blk: {
            crypto.hash.sha2.Sha384.hash(data, digest[0..48], .{});
            break :blk 48;
        },
        .sha512_256 => blk: {
            crypto.hash.sha2.Sha512_256.hash(data, digest[0..32], .{});
            break :blk 32;
        },
        .sha3_224 => blk: {
            crypto.hash.sha3.Sha3_224.hash(data, digest[0..28], .{});
            break :blk 28;
        },
        .sha3_384 => blk: {
            crypto.hash.sha3.Sha3_384.hash(data, digest[0..48], .{});
            break :blk 48;
        },
        .sha3_512 => blk: {
            crypto.hash.sha3.Sha3_512.hash(data, digest[0..64], .{});
            break :blk 64;
        },
        .shake128 => blk: {
            crypto.hash.sha3.Shake128.hash(data, digest[0..32], .{});
            break :blk 32;
        },
        .shake256 => blk: {
            crypto.hash.sha3.Shake256.hash(data, digest[0..32], .{});
            break :blk 32;
        },
        .blake2s256 => blk: {
            crypto.hash.blake2.Blake2s256.hash(data, digest[0..32], .{});
            break :blk 32;
        },
        .blake2b512 => blk: {
            crypto.hash.blake2.Blake2b512.hash(data, digest[0..64], .{});
            break :blk 64;
        },
    };

    const out = try gpa.alloc(u8, digest_len * 2);
    for (digest[0..digest_len], 0..) |b, i| {
        _ = std.fmt.bufPrint(out[2 * i ..][0..2], "{x:0>2}", .{b}) catch unreachable;
    }
    return out;
}

pub fn deriveKey(
    io: std.Io,
    gpa: mem.Allocator,
    kdf: Kdf,
    params: KdfParams,
    password: []const u8,
    salt: []const u8,
    dk_len: usize,
) ![]u8 {
    const dk = try gpa.alloc(u8, dk_len);
    errdefer gpa.free(dk);

    switch (kdf) {
        .argon2id => switch (params) {
            .argon2id => |p| try crypto.pwhash.argon2.kdf(
                gpa,
                dk,
                password,
                salt,
                .{ .m = p.m, .t = p.t, .p = p.p },
                .argon2id,
                io,
            ),
            else => unreachable,
        },
        .pbkdf2_sha256 => switch (params) {
            .pbkdf2_sha256 => |p| try crypto.pwhash.pbkdf2(
                dk,
                password,
                salt,
                p.rounds,
                crypto.auth.hmac.sha2.HmacSha256,
            ),
            else => unreachable,
        },
        .scrypt => switch (params) {
            .scrypt => |p| try crypto.pwhash.scrypt.kdf(
                gpa,
                dk,
                password,
                salt,
                .{ .ln = p.ln, .r = p.r, .p = p.p },
            ),
            else => unreachable,
        },
    }

    return dk;
}

fn defaultParams(kdf: Kdf) KdfParams {
    return switch (kdf) {
        .argon2id => .{ .argon2id = .{
            .m = crypto.pwhash.argon2.Params.interactive_2id.m,
            .t = crypto.pwhash.argon2.Params.interactive_2id.t,
            .p = crypto.pwhash.argon2.Params.interactive_2id.p,
        } },
        .pbkdf2_sha256 => .{ .pbkdf2_sha256 = .{ .rounds = 210_000 } },
        .scrypt => .{ .scrypt = .{
            .ln = crypto.pwhash.scrypt.Params.owasp.ln,
            .r = crypto.pwhash.scrypt.Params.owasp.r,
            .p = crypto.pwhash.scrypt.Params.owasp.p,
        } },
    };
}

fn writeHeader(
    buf: []u8,
    kdf: Kdf,
    aead: Aead,
    params: KdfParams,
) void {
    @memcpy(buf[0..4], magic);
    buf[4] = version;
    buf[5] = @intFromEnum(kdf);
    buf[6] = @intFromEnum(aead);
    buf[7] = 0;

    const costs = costsFromParams(kdf, params);
    mem.writeInt(u32, buf[8..12], costs[0], .little);
    mem.writeInt(u32, buf[12..16], costs[1], .little);
    mem.writeInt(u32, buf[16..20], costs[2], .little);
}

fn costsFromParams(kdf: Kdf, params: KdfParams) [3]u32 {
    return switch (kdf) {
        .argon2id => switch (params) {
            .argon2id => |p| .{ p.m, p.t, p.p },
            else => unreachable,
        },
        .pbkdf2_sha256 => switch (params) {
            .pbkdf2_sha256 => |p| .{ p.rounds, 0, 0 },
            else => unreachable,
        },
        .scrypt => switch (params) {
            .scrypt => |p| .{ @as(u32, 1) << @intCast(p.ln), p.r, p.p },
            else => unreachable,
        },
    };
}

fn paramsFromCosts(kdf: Kdf, cost1: u32, cost2: u32, cost3: u32) KdfParams {
    return switch (kdf) {
        .argon2id => .{ .argon2id = .{
            .m = cost1,
            .t = cost2,
            .p = @intCast(cost3),
        } },
        .pbkdf2_sha256 => .{ .pbkdf2_sha256 = .{ .rounds = cost1 } },
        .scrypt => .{ .scrypt = .{
            .ln = @intCast(@ctz(cost1)),
            .r = @intCast(cost2),
            .p = @intCast(cost3),
        } },
    };
}

fn parseKdf(id: u8) ?Kdf {
    if (id > @intFromEnum(Kdf.scrypt)) return null;
    return @enumFromInt(id);
}

fn parseAead(id: u8) ?Aead {
    if (id > @intFromEnum(Aead.chacha12_poly1305)) return null;
    return @enumFromInt(id);
}

test "modern roundtrip all kdf x aead combos" {
    var io_impl = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    const plaintext = "The quick brown fox jumps over the lazy dog 123!";
    const password = "hunter2";

    inline for (std.enums.values(Kdf)) |kdf| {
        inline for (std.enums.values(Aead)) |aead| {
            const opts = EncryptOptions{
                .kdf = kdf,
                .aead = aead,
                .kdf_params = tinyParams(kdf),
            };

            const enc = try encrypt(io, std.testing.allocator, password, plaintext, opts);
            defer std.testing.allocator.free(enc);

            const dec = try decrypt(io, std.testing.allocator, password, enc);
            defer std.testing.allocator.free(dec);

            try std.testing.expectEqualSlices(u8, plaintext, dec);
        }
    }
}

test "modern decrypt with tampered ciphertext fails auth" {
    var io_impl = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    const opts = EncryptOptions{ .kdf_params = tinyParams(.argon2id) };
    const enc = try encrypt(io, std.testing.allocator, "password", "top secret", opts);
    defer std.testing.allocator.free(enc);

    var tampered = try std.testing.allocator.dupe(u8, enc);
    defer std.testing.allocator.free(tampered);
    const last = tampered.len - 1;
    tampered[last] = switch (tampered[last]) {
        'A' => 'B',
        else => 'A',
    };

    try std.testing.expectError(
        error.AuthenticationFailed,
        decrypt(io, std.testing.allocator, "password", tampered),
    );
}

test "modern decrypt with wrong password fails auth" {
    var io_impl = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    const opts = EncryptOptions{ .kdf_params = tinyParams(.argon2id) };
    const enc = try encrypt(io, std.testing.allocator, "password", "top secret", opts);
    defer std.testing.allocator.free(enc);

    try std.testing.expectError(
        error.AuthenticationFailed,
        decrypt(io, std.testing.allocator, "wrong-password", enc),
    );
}

test "modern hash known vectors" {
    const gpa = std.testing.allocator;

    const h1 = try hash(gpa, .sha256, "abc");
    defer gpa.free(h1);
    try std.testing.expectEqualStrings(
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        h1,
    );

    const h2 = try hash(gpa, .sha512, "abc");
    defer gpa.free(h2);
    try std.testing.expectEqualStrings(
        "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" ++
            "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
        h2,
    );

    const h3 = try hash(gpa, .sha3_256, "abc");
    defer gpa.free(h3);
    try std.testing.expectEqualStrings(
        "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
        h3,
    );

    const h4 = try hash(gpa, .blake3, "");
    defer gpa.free(h4);
    try std.testing.expectEqualStrings(
        "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
        h4,
    );
}

test "modern hash extended vectors" {
    const gpa = std.testing.allocator;

    const vectors = [_]struct { algo: HashAlgo, data: []const u8, want: []const u8 }{
        .{ .algo = .md5, .data = "abc", .want = "900150983cd24fb0d6963f7d28e17f72" },
        .{ .algo = .sha1, .data = "abc", .want = "a9993e364706816aba3e25717850c26c9cd0d89d" },
        .{ .algo = .sha224, .data = "abc", .want = "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7" },
        .{ .algo = .sha384, .data = "abc", .want = "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7" },
        .{ .algo = .sha512_256, .data = "abc", .want = "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23" },
        .{ .algo = .sha3_224, .data = "abc", .want = "e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf" },
        .{ .algo = .sha3_384, .data = "abc", .want = "ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25" },
        .{ .algo = .sha3_512, .data = "abc", .want = "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0" },
        .{ .algo = .blake2s256, .data = "abc", .want = "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982" },
        .{ .algo = .blake2b512, .data = "abc", .want = "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923" },
    };

    for (vectors) |v| {
        const out = try hash(gpa, v.algo, v.data);
        defer gpa.free(out);
        try std.testing.expectEqualStrings(v.want, out);
    }

    const s1 = try hash(gpa, .shake128, "abc");
    defer gpa.free(s1);
    const s2 = try hash(gpa, .shake256, "abc");
    defer gpa.free(s2);
    try std.testing.expectEqual(@as(usize, 64), s1.len);
    try std.testing.expectEqual(@as(usize, 64), s2.len);
}

fn tinyParams(kdf: Kdf) KdfParams {
    return switch (kdf) {
        .argon2id => .{ .argon2id = .{ .m = 32, .t = 1, .p = 1 } },
        .pbkdf2_sha256 => .{ .pbkdf2_sha256 = .{ .rounds = 1000 } },
        .scrypt => .{ .scrypt = .{ .ln = 10, .r = 8, .p = 1 } },
    };
}
