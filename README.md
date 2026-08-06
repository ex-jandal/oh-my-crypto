# Oh My Crypto

<p align="center">
  <img src="./assets/screenshot.png" width="500" alt="Screenshot"/>
</p>

A desktop GUI crypto utility written in **Zig 0.16.0** with **Qt 6** bindings via
[`libqt6zig`](https://github.com/rcalixte/libqt6zig). Encrypt and decrypt text with
six classical ciphers:

| Cipher        | Transformation                              | Key            |
| ------------- | ------------------------------------------- | -------------- |
| Caesar        | `E(x) = (x + k) mod 26`                     | shift `k`      |
| Multiplicative| `E(x) = (k · x) mod 26`                     | key `k`        |
| Affine        | `E(x) = (a · x + b) mod 26`                 | `(a, b)`       |
| Autokey       | key stream = keyword + running plaintext    | keyword        |
| Vigenère      | key stream = keyword, repeated cyclically   | keyword        |
| Zigzag        | letters rearranged in a rail-fence pattern  | rails `r`      |

> **Educational tool.** These ciphers are trivially breakable with modern
> frequency analysis. Use them to learn cryptography, not to protect data.

## Features

- Qt 6 native GUI (widgets) — no web view, no Tkinter
- Home menu navigating stacked pages: Text, File, About
- **Text page** — encrypt/decrypt user-typed text with per-cipher key inputs:
  - shift spinbox 0–25 (Caesar)
  - key spinbox 0–25, auto-validated against `gcd(k, 26) = 1` (multiplicative)
  - `a` and `b` spinboxes, `a` auto-validated (affine)
  - keyword line edit (autokey, Vigenère)
  - rails spinbox 2–10 (zigzag)
- **File page** — open a `.txt` file with a native dialog, encrypt or decrypt
  its content, and save the result to a new file
- Substitution ciphers preserve spaces, digits, and punctuation; only
  `A–Z` / `a–z` are transformed. Zigzag permutes letters only and keeps
  non-letter characters in place.
- Case preserved per letter
- Copy/paste friendly plain text areas
- Ayu dark theme with an animated glowing homepage title
- Invalid keys and other errors reported in the status line and message dialogs

## Requirements

- Zig **0.16.0** (latest stable)
- Qt **6.8+** development files.
- C and C++ toolchain (`gcc` / `clang`, `libstdc++`)

## Build

```bash
zig build            # build binary into zig-out/bin
zig build run        # build and run
zig build test       # run cipher unit tests
zig build -Doptimize=ReleaseSafe   # release build
```

The binary is written to `zig-out/bin/omc`.

Dependencies are declared in `build.zig.zon` and fetched automatically. The
first build compiles the linked subset of `libqt6zig` — expect a few minutes on
a cold cache; subsequent builds take seconds.

## Project layout

```
build.zig          # build script: Qt module wiring + artifact links
build.zig.zon      # dependency manifest (libqt6zig pinned)
src/
  main.zig         # Qt application entry point + main window
  root.zig         # library module root (exports shared cipher logic)
  cipher.zig       # cipher math module (encrypt/decrypt for all 6 ciphers)
  pages.zig        # GUI pages, widget state, and signal callbacks
  style.zig        # stylesheet import
  ayu_dark.qss     # ayu dark theme
```

## License

MIT — see [LICENSE](LICENSE).

Qt is licensed separately (LGPL/GPL/commercial) — meet your obligations under
[Qt licensing](https://doc.qt.io/qt-6/licensing.html).
