# GUIDE — Building Oh My Crypto from Scratch

A hands-on walkthrough for building a Qt 6 desktop crypto tool in Zig 0.16.0
using the `libqt6zig` bindings. Follow the sections in order. Each section ends
with a concrete, copy-pasteable artifact.

---

## 1. Prerequisites

You need three toolchains:

| Tool       | Version / package                                  | Purpose            |
| ---------- | -------------------------------------------------- | ------------------ |
| Zig        | 0.16.0 (stable)                                    | build + language   |
| Qt 6       | 6.8+ dev packages                                  | GUI framework      |
| C/C++      | `gcc` + `libstdc++` (or clang)                     | C ABI + Qt linkage |

### Zig 0.16.0

Check your version first:

```bash
zig version   # must print 0.16.0
```

If it prints an older version, install 0.16.0 from
<https://ziglang.org/download/>. Do not rely on distro packages — they are
usually outdated.

### Qt 6.8+ + toolchain

`libqt6zig` dynamically links against the system Qt libraries, so you need the
`-dev` (headers + libraries) packages.

**Debian/Ubuntu:**

```bash
sudo apt install gcc libstdc++-14-dev qt6-base-dev qt6-base-private-dev
```

**Arch:**

```bash
sudo pacman -S gcc qt6-base
```

**Fedora:**

```bash
sudo dnf install gcc libstdc++-devel qt6-qtbase-devel
```

**openSUSE:**

```bash
sudo zypper install gcc qt6-base-devel
```

Verify Qt is discoverable:

```bash
pkg-config --modversion Qt6Widgets   # e.g. 6.8.2
```

The full optional-dependency list (charts, KDE frameworks, etc.) is in the
[libqt6zig README](https://github.com/rcalixte/libqt6zig) — you only need
`qt6-base`.

---

## 2. Initialize the project and fetch the binding

```bash
mkdir oh-my-crypto && cd oh-my-crypto
zig init                       # creates build.zig, build.zig.zon, src/
zig fetch --save git+https://github.com/rcalixte/libqt6zig
```

`zig fetch --save` pins the latest commit and hash into `build.zig.zon` under
`.dependencies.libqt6zig`. A pinned entry looks like:

```zig
.dependencies = .{
    .libqt6zig = .{
        .url = "git+https://github.com/rcalixte/libqt6zig#<commit>",
        .hash = "libqt6zig-6.8.2-<hash>",
    },
},
```

The fetched package lands in `zig-pkg/` and is fully cached — no network needed
on subsequent builds.

> **Tip:** pin a known-good commit (as this repo does) instead of floating on
> `master`. `libqt6zig` tracks Qt 6.8+ and breaking changes are possible.

---

## 3. Wire `build.zig`

Three things must happen in the build script:

1. Declare the dependency.
2. Import the `libqt6zig` module into the executable.
3. Link exactly the Qt class artifacts you use.

```zig
const qt6zig = b.dependency("libqt6zig", .{
    .target = target,
    .optimize = .ReleaseFast,   // bindings are large; keep them optimized
});

// after the executable is defined:
exe.root_module.addImport("libqt6zig", qt6zig.module("libqt6zig"));

const required_artifacts = [_][]const u8{
    "qapplication",
    "qwidget",
    "qmainwindow",        // or qwidget for a plain window
    "qboxlayout",         // QVBoxLayout / QHBoxLayout
    "qformlayout",
    "qlabel",
    "qlineedit",
    "qcombobox",
    "qspinbox",
    "qplaintextedit",
    "qpushbutton",
    "qgroupbox",
    "qevent",             // needed by event callback signatures
};
inline for (required_artifacts) |art| {
    exe.root_module.linkLibrary(qt6zig.artifact(art));
}

// convenience helper: sets include paths, lib paths, rpath, etc.
const configureQtExeRootModule = @import("libqt6zig").configureQtExeRootModule;
try configureQtExeRootModule(b, exe, .{});
```

Artifact name = Qt class name in lowercase, minus the `lib` prefix and extension
(`qapplication`, `qwidget`, …). Only list what you import — the build stays
small. The current `build.zig` in this repo links the core set; add
`qlineedit`, `qcombobox`, `qspinbox`, `qplaintextedit`, `qformlayout`,
`qpushbutton`, `qgroupbox` when you build the crypto UI.

---

## 4. The cipher math module — `src/cipher.zig`

Keep cipher logic free of any Qt dependency so it stays unit-testable from the
command line. Export it from `src/root.zig`:

```zig
pub const cipher = @import("cipher.zig");
```

`libqt6zig` projects Qt strings as plain Zig `[]const u8`, so the cipher module
operates on plain slices — no `QString` wrangling.

### 4.1 Shared helpers

```zig
const std = @import("std");

pub const Cipher = enum { caesar, additive, multiplicative, affine, autokey, vigenere, zigzag };

const A_LOWER: u8 = 'a';
const A_UPPER: u8 = 'A';
const MOD: i32 = 26; // keep arithmetic in i32 so @mod never mixes types

fn isAlpha(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

/// 'A'..'Z' and 'a'..'z' -> 0..25 (u8 widens to i32 implicitly)
fn toIdx(ch: u8) i32 {
    if (ch >= 'a' and ch <= 'z') return ch - A_LOWER;
    return ch - A_UPPER;
}

fn fromIdx(idx: i32, isUpper: bool) u8 {
    return (if (isUpper) A_UPPER else A_LOWER) + @as(u8, @intCast(@mod(idx, MOD)));
}

/// Transform one letter by +delta (encrypt) or -delta (decrypt), preserving case.
fn shiftOne(ch: u8, delta: i32, mode: enum { encrypt, decrypt }) u8 {
    if (!isAlpha(ch)) return ch; // spaces, digits, punctuation pass through
    const idx = toIdx(ch);
    const step = if (mode == .encrypt) delta else -delta;
    return fromIdx(@mod(idx + step, MOD), ch >= 'A' and ch <= 'Z');
}
```

> **`@mod` vs `%`:** Zig's `%` is C-style remainder (can be negative).
> `@mod` always returns a non-negative result — that is what modular-arithmetic
> ciphers need for decryption.

### 4.2 Caesar and additive

Both are `E(x) = (x + k) mod 26`. They share one implementation; the UI just
labels the key differently (Caesar's classic shift of 3 vs. any key 0–25).

```zig
pub fn shiftEncrypt(alloc: std.mem.Allocator, text: []const u8, key: u8) ![]u8 {
    const out = try alloc.alloc(u8, text.len);
    for (text, 0..) |ch, i| out[i] = shiftOne(ch, @intCast(key), .encrypt);
    return out;
}

pub fn shiftDecrypt(alloc: std.mem.Allocator, text: []const u8, key: u8) ![]u8 {
    const out = try alloc.alloc(u8, text.len);
    for (text, 0..) |ch, i| out[i] = shiftOne(ch, @intCast(key), .decrypt);
    return out;
}
```

`shiftEncrypt`/`shiftDecrypt` serve both Caesar and additive. Caller owns the
returned slice and must `alloc.free` it.

### 4.3 Multiplicative

`E(x) = (k · x) mod 26`. A key only works if `gcd(k, 26) = 1`; otherwise two
different plaintext letters collide (the map is not one-to-one) and decryption
is impossible.

```zig
pub fn gcd(a: u64, b: u64) u64 {
    var x = a;
    var y = b;
    while (y != 0) {
        const t = x % y;
        x = y;
        y = t;
    }
    return x;
}

/// Modular inverse of `a` mod 26 via extended Euclidean algorithm.
pub fn modInv(a: i64) ?i64 {
    var t: i64 = 0;
    var new_t: i64 = 1;
    var r: i64 = 26;
    var new_r: i64 = @mod(a, 26);
    while (new_r != 0) {
        const q = @divTrunc(r, new_r);
        const old_t = t; t = new_t; new_t = old_t - q * new_t;
        const old_r = r; r = new_r; new_r = old_r - q * new_r;
    }
    if (r != 1) return null; // not invertible mod 26
    return @mod(t, 26);
}

pub fn mulKeyValid(key: u8) bool {
    return gcd(key, 26) == 1;
}

pub fn mulEncrypt(alloc: std.mem.Allocator, text: []const u8, key: u8) ![]u8 {
    const out = try alloc.alloc(u8, text.len);
    for (text, 0..) |ch, i| {
        out[i] = if (isAlpha(ch))
            fromIdx(@mod(toIdx(ch) * key, MOD), ch >= 'A' and ch <= 'Z')
        else
            ch;
    }
    return out;
}

pub fn mulDecrypt(alloc: std.mem.Allocator, text: []const u8, key: u8) ![]u8 {
    const inv = modInv(key) orelse return error.KeyNotInvertible;
    const out = try alloc.alloc(u8, text.len);
    for (text, 0..) |ch, i| {
        out[i] = if (isAlpha(ch))
            fromIdx(@mod(toIdx(ch) * inv, MOD), ch >= 'A' and ch <= 'Z')
        else
            ch;
    }
    return out;
}
```

Valid multiplicative keys: 1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25.

### 4.4 Affine

`E(x) = (a·x + b) mod 26`, `D(y) = a⁻¹·(y − b) mod 26`. Requires
`gcd(a, 26) = 1`; `b` can be anything 0–25. This is multiplicative + additive
combined — implement it on top of the same helpers.

```zig
pub fn affineValid(a: u8) bool {
    return gcd(a, 26) == 1;
}

pub fn affineEncrypt(alloc: std.mem.Allocator, text: []const u8, a: u8, b: u8) ![]u8 {
    const out = try alloc.alloc(u8, text.len);
    for (text, 0..) |ch, i| {
        if (!isAlpha(ch)) { out[i] = ch; continue; }
        const v = @mod(toIdx(ch) * a + b, MOD);
        out[i] = fromIdx(v, ch >= 'A' and ch <= 'Z');
    }
    return out;
}

pub fn affineDecrypt(alloc: std.mem.Allocator, text: []const u8, a: u8, b: u8) ![]u8 {
    const inv = modInv(a) orelse return error.KeyNotInvertible;
    const out = try alloc.alloc(u8, text.len);
    for (text, 0..) |ch, i| {
        if (!isAlpha(ch)) { out[i] = ch; continue; }
        const v = @mod(inv * (toIdx(ch) - b), MOD);
        out[i] = fromIdx(@intCast(v), ch >= 'A' and ch <= 'Z');
    }
    return out;
}
```

### 4.5 Autokey

A Vigenère variant where the key stream is the keyword followed by the running
plaintext:

```
key stream:   K E Y A T T A C K A T D …
plaintext:    A T T A C K A T D A W N …
ciphertext:   K X R A V D A V N A P Q …
```

Encryption only ever needs the keyword: for pure-alphabet text, keystream char
`i` is `keyword[i]` while `i < keyword.len`, then `plaintext[i - keyword.len]`.

Decryption is trickier: you need the running plaintext to extend the keystream,
so you must recover letters one at a time and feed them back. Preserve
non-alphabet characters but **do not** advance the keystream position for them —
they don't participate in the cipher.

Both directions must track keystream position as a count of **alpha chars
only** — spaces and punctuation do not participate in the cipher and must not
advance the keystream. Keep a scratch buffer of the running plaintext indexed by
alpha position:

```zig
pub fn autoEncrypt(alloc: std.mem.Allocator, text: []const u8, keyword: []const u8) ![]u8 {
    if (keyword.len == 0) return error.EmptyKey;
    const out = try alloc.alloc(u8, text.len);
    const alpha = try alloc.alloc(u8, text.len); // plaintext letters, in order
    defer alloc.free(alpha);
    var n: usize = 0; // alpha-chars processed == keystream position
    for (text, 0..) |ch, i| {
        if (!isAlpha(ch)) { out[i] = ch; continue; }
        const key_ch = if (n < keyword.len) keyword[n] else alpha[n - keyword.len];
        out[i] = shiftOne(ch, @intCast(toIdx(key_ch)), .encrypt);
        alpha[n] = ch; // this plaintext letter feeds the future keystream
        n += 1;
    }
    return out;
}

pub fn autoDecrypt(alloc: std.mem.Allocator, text: []const u8, keyword: []const u8) ![]u8 {
    if (keyword.len == 0) return error.EmptyKey;
    const out = try alloc.alloc(u8, text.len);
    const alpha = try alloc.alloc(u8, text.len); // recovered plaintext letters
    defer alloc.free(alpha);
    var n: usize = 0;
    for (text, 0..) |ch, i| {
        if (!isAlpha(ch)) { out[i] = ch; continue; }
        const key_ch = if (n < keyword.len) keyword[n] else alpha[n - keyword.len];
        const p = shiftOne(ch, @intCast(toIdx(key_ch)), .decrypt);
        out[i] = p;
        alpha[n] = p; // recovered plaintext extends the keystream
        n += 1;
    }
    return out;
}
```

The essential trick: at alpha position `n >= keyword.len`, the keystream letter
is the plaintext letter from alpha position `n - keyword.len` — available
immediately for decryption because you recover letters left to right.

### 4.6 Vigenère

The classic Vigenère: the keyword repeats cyclically as the keystream
(`KEYKEYKEY…`), and each letter is shifted by the keyword letter's index. This is
autokey with the "running plaintext" part deleted — which makes it *harder*, not
easier, to implement: with autokey the keystream extended itself from the
plaintext, but here the keystream is *only* the keyword, so the loop needs a
plain index into the keyword.

```zig
pub fn vigenereEncrypt(alloc: std.mem.Allocator, text: []const u8, keyword: []const u8) ![]u8 {
    if (keyword.len == 0) return error.EmptyKey;
    const out = try alloc.alloc(u8, text.len);
    var n: usize = 0; // alpha chars processed == keystream position
    for (text, 0..) |ch, i| {
        if (!isAlpha(ch)) { out[i] = ch; continue; }
        const key_ch = keyword[n % keyword.len];
        out[i] = shiftOne(ch, @intCast(toIdx(key_ch)), .encrypt);
        n += 1;
    }
    return out;
}

pub fn vigenereDecrypt(alloc: std.mem.Allocator, text: []const u8, keyword: []const u8) ![]u8 {
    if (keyword.len == 0) return error.EmptyKey;
    const out = try alloc.alloc(u8, text.len);
    var n: usize = 0;
    for (text, 0..) |ch, i| {
        if (!isAlpha(ch)) { out[i] = ch; continue; }
        const key_ch = keyword[n % keyword.len];
        out[i] = shiftOne(ch, @intCast(toIdx(key_ch)), .decrypt);
        n += 1;
    }
    return out;
}
```

Same discipline as autokey: count only alpha chars in `n` so spaces and
punctuation don't consume keystream letters, and `n % keyword.len` cycles the
keyword. Known vector: `VIG_ENCRYPT("ATTACKATDAWN", "LEMON") = "LXFOPVEFRNHR"`.

### 4.7 Zigzag (rail fence)

A pure **transposition** cipher — no substitution, so `isAlpha` is irrelevant and
*every* character (spaces, digits, punctuation included) participates. Write the
plaintext down `rails` rows in a zigzag pattern, then read row by row:

```
r0: W . . . E . . . C . . . R . . . L . . . T . . . E
r1: . E . R . D . S . O . E . E . F . E . A . O . C .
r2: . . A . . . I . . . V . . . D . . . E . . . N . .
```

The zigzag pattern is periodic with period `2 * (rails - 1)`: rail `i` is `i mod
period` while below the middle, then mirrored on the way back up. Compute the
destination rail directly from the position index — no need to simulate the
bouncing pointer.

```zig
fn railAt(i: usize, rails: usize) usize {
    const mid = rails - 1;
    const pos = i % (2 * mid);
    return if (pos < mid) pos else 2 * mid - pos;
}

pub fn zigzagEncrypt(alloc: std.mem.Allocator, text: []const u8, rails: usize) ![]u8 {
    if (rails < 2) return error.InvalidRails;
    const out = try alloc.alloc(u8, text.len);
    const counts = try alloc.alloc(usize, rails);
    defer alloc.free(counts);
    @memset(counts, 0);
    for (0..text.len) |i| counts[railAt(i, rails)] += 1;

    const offs = try alloc.alloc(usize, rails); // next free slot per rail
    defer alloc.free(offs);
    var acc: usize = 0;
    for (0..rails) |r| { offs[r] = acc; acc += counts[r]; }

    for (text, 0..) |ch, i| {
        const r = railAt(i, rails);
        out[offs[r]] = ch;
        offs[r] += 1;
    }
    return out;
}
```

Decryption inverts the same walk: count the positions per rail, split the
ciphertext into `rails` consecutive chunks (rail `r` starts at the running sum
of the counts), then replay the zigzag reading one char from each rail's chunk
in order:

```zig
pub fn zigzagDecrypt(alloc: std.mem.Allocator, text: []const u8, rails: usize) ![]u8 {
    if (rails < 2) return error.InvalidRails;
    const n = text.len;
    const counts = try alloc.alloc(usize, rails);
    defer alloc.free(counts);
    @memset(counts, 0);
    for (0..n) |i| counts[railAt(i, rails)] += 1;

    const starts = try alloc.alloc(usize, rails); // chunk offset of rail r in `text`
    defer alloc.free(starts);
    var acc: usize = 0;
    for (0..rails) |r| { starts[r] = acc; acc += counts[r]; }

    const pos = try alloc.alloc(usize, rails); // read cursor per rail
    defer alloc.free(pos);
    @memset(pos, 0);

    const out = try alloc.alloc(u8, n);
    for (0..n) |i| {
        const r = railAt(i, rails);
        out[i] = text[starts[r] + pos[r]];
        pos[r] += 1;
    }
    return out;
}
```

Known vector: `ZIGZAG_ENCRYPT("WEAREDISCOVEREDFLEEATONCE", 3) =
"WECRLTEERDSOEEFEAOCAIVDEN"`. Rails must be ≥ 2; `railAt` divides by
`2 * (rails - 1)`, so anything less is rejected up front.

---

## 5. Unit tests — the cheap safety net

The cipher module is pure Zig, so test it without Qt. Add blocks at the bottom
of `cipher.zig`:

```zig
test "caesar roundtrip" {
    const alloc = std.testing.allocator;
    const ct = try shiftEncrypt(alloc, "ATTACK AT DAWN", 3);
    defer alloc.free(ct);
    const pt = try shiftDecrypt(alloc, ct, 3);
    defer alloc.free(pt);
    try std.testing.expectEqualStrings("ATTACK AT DAWN", pt);
}

test "multiplicative invalid key rejected" {
    try std.testing.expect(mulKeyValid(2) == false);   // gcd(2,26)=2
    try std.testing.expect(mulKeyValid(5) == true);    // gcd(5,26)=1
}

test "affine roundtrip" {
    const alloc = std.testing.allocator;
    const ct = try affineEncrypt(alloc, "HELLO", 5, 8);
    defer alloc.free(ct);
    const pt = try affineDecrypt(alloc, ct, 5, 8);
    defer alloc.free(pt);
    try std.testing.expectEqualStrings("HELLO", pt);
}

test "autokey roundtrip" {
    const alloc = std.testing.allocator;
    const kw = "KEY";
    const ct = try autoEncrypt(alloc, "ATTACKATDAWN", kw);
    defer alloc.free(ct);
    const pt = try autoDecrypt(alloc, ct, kw);
    defer alloc.free(pt);
    try std.testing.expectEqualStrings("ATTACKATDAWN", pt);
}

test "vigenere known vector" {
    const alloc = std.testing.allocator;
    const ct = try vigenereEncrypt(alloc, "ATTACKATDAWN", "LEMON");
    defer alloc.free(ct);
    try std.testing.expectEqualStrings("LXFOPVEFRNHR", ct);
    const pt = try vigenereDecrypt(alloc, ct, "LEMON");
    defer alloc.free(pt);
    try std.testing.expectEqualStrings("ATTACKATDAWN", pt);
}

test "vigenere skips non-alpha, counts alpha only" {
    const alloc = std.testing.allocator;
    const ct = try vigenereEncrypt(alloc, "Attack at dawn!", "LEMON");
    defer alloc.free(ct);
    try std.testing.expectEqualStrings("Lxfopv ef rnhr!", ct); // same shifts as vector above
    const pt = try vigenereDecrypt(alloc, ct, "LEMON");
    defer alloc.free(pt);
    try std.testing.expectEqualStrings("Attack at dawn!", pt);
}

test "vigenere empty key rejected" {
    try std.testing.expectError(error.EmptyKey, vigenereEncrypt(std.testing.allocator, "hi", ""));
}

test "zigzag known vector" {
    const alloc = std.testing.allocator;
    const ct = try zigzagEncrypt(alloc, "WEAREDISCOVEREDFLEEATONCE", 3);
    defer alloc.free(ct);
    try std.testing.expectEqualStrings("WECRLTEERDSOEEFEAOCAIVDEN", ct);
    const pt = try zigzagDecrypt(alloc, ct, 3);
    defer alloc.free(pt);
    try std.testing.expectEqualStrings("WEAREDISCOVEREDFLEEATONCE", pt);
}

test "zigzag keeps spaces and punctuation" {
    const alloc = std.testing.allocator;
    const ct = try zigzagEncrypt(alloc, "WE ARE DISCOVERED FLEE AT ONCE", 4);
    defer alloc.free(ct);
    const pt = try zigzagDecrypt(alloc, ct, 4);
    defer alloc.free(pt);
    try std.testing.expectEqualStrings("WE ARE DISCOVERED FLEE AT ONCE", pt);
}

test "zigzag too few rails rejected" {
    try std.testing.expectError(error.InvalidRails, zigzagEncrypt(std.testing.allocator, "hi", 1));
}
```

Known vectors for the sanity checks above:

```
AUTO_ENCRYPT("ATTACKATDAWN", "KEY")     = "KXRAVDAVNAPQ"
AUTO_DECRYPT("KXRAVDAVNAPQ", "KEY")     = "ATTACKATDAWN"
VIG_ENCRYPT("ATTACKATDAWN", "LEMON")    = "LXFOPVEFRNHR"
ZIGZAG_ENCRYPT("WEAREDISCOVEREDFLEEATONCE", 3) = "WECRLTEERDSOEEFEAOCAIVDEN"
```

Trace of the autokey first few positions: keystream is `KEY + ATTACK…`, so
`A+K=K`, `T+E=X`, `T+Y=R` (43 mod 26 = 17), `A+A=A`, `C+T=V`, `K+T=D`.
The Vigenère trace is the same minus the self-extension: keystream is
`LEMONLEMON…`. The rail-fence vector is a pure permutation — the 25 plaintext
letters come back, rearranged.

Run with `zig build test`. Fix the math here before touching the GUI.

---

## 6. The Qt application — `src/main.zig`

### 6.1 Skeleton (lifecycle)

`libqt6zig` follows a fixed startup dance: init Qt, create `QApplication`,
build widgets, enter the event loop.

```zig
const std = @import("std");
const qt6 = @import("libqt6zig");
const QApplication = qt6.QApplication;
const QWidget = qt6.QWidget;
const QGroupBox = qt6.QGroupBox;
const QComboBox = qt6.QComboBox;
const QSpinBox = qt6.QSpinBox;
const QLineEdit = qt6.QLineEdit;
const QPlainTextEdit = qt6.QPlainTextEdit;
const QPushButton = qt6.QPushButton;
const QLabel = qt6.QLabel;
const QVBoxLayout = qt6.QVBoxLayout;
const QHBoxLayout = qt6.QHBoxLayout;
const QFormLayout = qt6.QFormLayout;
const qnamespace_enums = qt6.qnamespace_enums;

pub fn main(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);

    var argc: i32 = @intCast(argv.len);
    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    const window = QWidget.New2();
    defer window.Delete();
    window.SetWindowTitle("Oh My Crypto");
    window.Resize(560, 640);
    window.Show();

    _ = QApplication.Exec();
}
```

Notes:

- `qt6.init` must be the first call; `init.gpa` is the general-purpose
  allocator and `init.minimal.args` the raw argv.
- `QApplication.New` takes an allocator (the arena is fine — it lives for the
  process) and mutable argc/argv.
- Deferred `Delete()` calls are essential; widget children that take a `parent`
  are owned by Qt and must **not** be deleted manually.

### 6.2 The widget tree

Since the Qt API is one big C ABI, the ergonomic pattern is: create widgets as
top-level `var` globals or capture them in callbacks, and connect signals after
construction. Build the tree bottom-up (innermost layouts first):

```zig
// --- top-level state shared by callbacks
var cipher_combo: QComboBox = undefined;
var shift_spin: QSpinBox = undefined;
var key_spin: QSpinBox = undefined;
var mul_spin: QSpinBox = undefined;
var a_spin: QSpinBox = undefined;
var b_spin: QSpinBox = undefined;
var keyword_edit: QLineEdit = undefined;
var rails_spin: QSpinBox = undefined;
var input_text: QPlainTextEdit = undefined;
var output_text: QPlainTextEdit = undefined;
var status_label: QLabel = undefined;
```

```zig
// --- key field group
const key_group = QGroupBox.New3("Key"); // no defer: reparented to window
const key_form = QFormLayout.New2();

cipher_combo = QComboBox.New2();
cipher_combo.AddItem("Caesar");
cipher_combo.AddItem("Additive");
cipher_combo.AddItem("Multiplicative");
cipher_combo.AddItem("Affine");
cipher_combo.AddItem("Autokey");
cipher_combo.AddItem("Vigenère");
cipher_combo.AddItem("Zigzag");

shift_spin = QSpinBox.New2();  shift_spin.SetRange(1, 25); shift_spin.SetValue(3);
key_spin   = QSpinBox.New2();  key_spin.SetRange(0, 25);   key_spin.SetValue(5);
mul_spin   = QSpinBox.New2();  mul_spin.SetRange(1, 25);   mul_spin.SetValue(5);
a_spin     = QSpinBox.New2();  a_spin.SetRange(1, 25);     a_spin.SetValue(5);
b_spin     = QSpinBox.New2();  b_spin.SetRange(0, 25);     b_spin.SetValue(8);
keyword_edit = QLineEdit.New3("KEY");
keyword_edit.SetPlaceholderText("keyword (autokey / vigenère)");
rails_spin = QSpinBox.New2();  rails_spin.SetRange(2, 10); rails_spin.SetValue(3);

key_form.AddRow3("Cipher:", cipher_combo);
key_form.AddRow3("Shift (Caesar):", shift_spin);
key_form.AddRow3("Key (additive):", key_spin);
key_form.AddRow3("Multiplier (m):", mul_spin);
key_form.AddRow3("a (affine):", a_spin);
key_form.AddRow3("b (affine):", b_spin);
key_form.AddRow3("Keyword:", keyword_edit);
key_form.AddRow3("Rails (zigzag):", rails_spin);
key_group.SetLayout(key_form);
```

Then the text areas and buttons:

```zig
input_text = QPlainTextEdit.New2();
input_text.SetPlaceholderText("Plaintext / ciphertext");
output_text = QPlainTextEdit.New2();
output_text.SetReadOnly(true);

const encrypt_btn = QPushButton.New5("Encrypt →", window);
const decrypt_btn = QPushButton.New5("← Decrypt", window);

const btn_row = QHBoxLayout.New2();
btn_row.AddWidget(encrypt_btn);
btn_row.AddWidget(decrypt_btn);

status_label = QLabel.New2();
status_label.SetWordWrap(true);
```

Finally, assemble the window layout:

```zig
const root = QVBoxLayout.New2();
root.AddWidget(key_group);
root.AddWidget(input_text);
root.AddLayout(btn_row);
root.AddWidget(output_text);
root.AddWidget(status_label);
window.SetLayout(root);
```

> `AddRow3(labelText, field)` is the convenience overload that takes a Zig
> string label. Widgets added to a layout with a parent widget are owned by Qt —
> don't call `Delete()` on them.

### 6.3 Signals

`libqt6zig` projects Qt signals as `OnSignalName(callback)` where callbacks use
`callconv(.c)`.

**Cipher switch → show only relevant key fields:**

```zig
fn onCipherChanged(_: QComboBox, _: i32) callconv(.c) void {
    const idx = cipher_combo.CurrentIndex();
    shift_spin.SetVisible(idx == 0);
    key_spin.SetVisible(idx == 1);
    mul_spin.SetVisible(idx == 2);
    a_spin.SetVisible(idx == 3);
    b_spin.SetVisible(idx == 3);
    keyword_edit.SetVisible(idx == 4 or idx == 5);
    rails_spin.SetVisible(idx == 6);
    runCrypto(); // live update
}
```

Note the callback arity: `OnCurrentIndexChanged` delivers the new index as a
second parameter — `fn (QComboBox, i32) callconv(.c) void`.

**Encrypt/decrypt buttons:**

```zig
var decrypt_mode: bool = false;

fn onEncrypt(_: QPushButton) callconv(.c) void {
    decrypt_mode = false;
    runCrypto();
}

fn onDecrypt(_: QPushButton) callconv(.c) void {
    decrypt_mode = true;
    runCrypto();
}
```

**The dispatcher — the heart of the app:**

```zig
fn runCrypto() void {
    const alloc = std.heap.page_allocator;
    const in = input_text.ToPlainText(alloc);
    defer alloc.free(in);

    const out = crypto(alloc, in) orelse {
        status_label.SetText("Invalid key for the selected cipher.");
        return;
    };
    defer alloc.free(out);

    output_text.SetPlainText(out);
    status_label.SetText("");
}

/// Returns an owned slice, or null when the key is invalid for the cipher.
fn crypto(alloc: std.mem.Allocator, text: []const u8) ?[]u8 {
    const idx = cipher_combo.CurrentIndex();
    return switch (idx) {
        0, 1 => shift(alloc, text, @intCast(shift_spin.Value())),
        2 => mul(alloc, text, @intCast(mul_spin.Value())),
        3 => affine(alloc, text, @intCast(a_spin.Value()), @intCast(b_spin.Value())),
        4 => autokey(alloc, text, keyword_edit.Text(alloc)),
        5 => vigenere(alloc, text, keyword_edit.Text(alloc)),
        6 => zigzag(alloc, text, @intCast(rails_spin.Value())),
        else => null,
    };
}

fn shift(alloc: std.mem.Allocator, text: []const u8, key: u8) ?[]u8 {
    return if (decrypt_mode)
        cipher.shiftDecrypt(alloc, text, key) catch null
    else
        cipher.shiftEncrypt(alloc, text, key) catch null;
}

fn mul(alloc: std.mem.Allocator, text: []const u8, key: u8) ?[]u8 {
    if (!cipher.mulKeyValid(key)) return null; // gcd(key, 26) must be 1
    return if (decrypt_mode)
        cipher.mulDecrypt(alloc, text, key) catch null
    else
        cipher.mulEncrypt(alloc, text, key) catch null;
}

fn affine(alloc: std.mem.Allocator, text: []const u8, a: u8, b: u8) ?[]u8 {
    if (!cipher.affineValid(a)) return null; // gcd(a, 26) must be 1
    return if (decrypt_mode)
        cipher.affineDecrypt(alloc, text, a, b) catch null
    else
        cipher.affineEncrypt(alloc, text, a, b) catch null;
}

fn autokey(alloc: std.mem.Allocator, text: []const u8, keyword: []const u8) ?[]u8 {
    defer alloc.free(keyword); // keyword came from keyword_edit.Text(alloc)
    if (keyword.len == 0) return null;
    return if (decrypt_mode)
        cipher.autoDecrypt(alloc, text, keyword) catch null
    else
        cipher.autoEncrypt(alloc, text, keyword) catch null;
}

fn vigenere(alloc: std.mem.Allocator, text: []const u8, keyword: []const u8) ?[]u8 {
    defer alloc.free(keyword); // same ownership rule as autokey
    if (keyword.len == 0) return null;
    return if (decrypt_mode)
        cipher.vigenereDecrypt(alloc, text, keyword) catch null
    else
        cipher.vigenereEncrypt(alloc, text, keyword) catch null;
}

fn zigzag(alloc: std.mem.Allocator, text: []const u8, rails: usize) ?[]u8 {
    if (rails < 2) return null;
    return if (decrypt_mode)
        cipher.zigzagDecrypt(alloc, text, rails) catch null
    else
        cipher.zigzagEncrypt(alloc, text, rails) catch null;
}
```

**Wire the signals — after every widget exists:**

```zig
cipher_combo.OnCurrentIndexChanged(onCipherChanged);
encrypt_btn.OnClicked(onEncrypt);
decrypt_btn.OnClicked(onDecrypt);
```

`OnClicked` takes a `fn (QPushButton) callconv(.c) void` (the button itself is
the only argument); `OnCurrentIndexChanged` takes
`fn (QComboBox, i32) callconv(.c) void`. Note that Qt fires
`OnCurrentIndexChanged` once immediately at connect time with the current index —
so `runCrypto()` runs once at startup with the default cipher/key, which is
harmless (empty input → empty output).

Watch the memory rules in this section:

- `ToPlainText(alloc)` and `Text(alloc)` **return slices you own** — free them.
- The cipher functions return slices you own — `SetPlainText` copies into Qt,
  it does not take ownership, so free after setting.
- Validation happens before each transform: invalid multiplicative/affine keys,
  empty keyword, and `rails < 2` produce `null`, and `runCrypto` reports it in
  the status label instead of writing garbage.

---

## 7. Wiring order checklist

In `main`, do things in this exact order or you will hit null widgets:

1. `qt6.init` → `QApplication.New`
2. Construct every widget (`New2`/`New3`/`New5`) **before** any `AddRow3`/`AddWidget`
3. Connect signals (`OnClicked`, `OnCurrentIndexChanged`) **after** the widgets they read are assigned
4. `window.SetLayout(root)`, `window.Show()`, `QApplication.Exec()`

---

## 8. Build and run

```bash
zig build            # compile -> zig-out/bin/omc
zig build run        # compile + launch the GUI
zig build test       # cipher unit tests only
```

First build: the linked `libqt6zig` artifacts (qapplication, qwidget, etc.) must
compile from source — several minutes on a cold cache. Warm-cache rebuilds are
seconds.

Common errors:

| Error                                             | Fix                                          |
| ------------------------------------------------- | -------------------------------------------- |
| `error: no module named 'libqt6zig'`              | missing `exe.root_module.addImport`          |
| `undefined symbol: _ZN…QLineEdit…`               | artifact `qlineedit` not linked in `build.zig` |
| `libQt6Widgets.so.6: cannot open shared object`   | install Qt dev packages, check `ldd zig-out/bin/omc` |
| segfault on close                                 | double-free: widget passed a `parent` must not also be `Delete()`d |

---

## 9. Going further

- **Frequency analysis panel:** count letter frequencies per ciphertext and
  compare against English `ETAOIN SHRDLU` to break any of these ciphers.
- **Save/load:** wire `QFileDialog` to persist plaintext/ciphertext (artifact
  `qfiledialog`).
- **Clipboard buttons:** `QApplication.Clipboard().SetText(...)` /
  `Text(...)` (artifact `qclipboard`).
- **Styling:** `window.SetStyleSheet("QPushButton { font-weight: bold; }")`.
- **Qt Designer forms:** `libqt6zig` ships `uic-zig` / `qrc-zig` tooling for
  `.ui` files — see the upstream README's Tools section.

Every step above maps to the exact API surface of the pinned `libqt6zig`
release in `build.zig.zon`. When in doubt, the generated Zig sources in
`zig-pkg/libqt6zig-*/include/*.zig` are the ground truth for signatures.
