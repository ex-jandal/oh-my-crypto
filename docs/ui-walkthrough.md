# Oh My Crypto — UI walkthrough

A function-by-function walkthrough of the Qt6 GUI, written against the current
source (main.zig `47` lines, sidebar.zig `123`, theme.zig `89`, pages.zig `1018`).
Every section dumps the real code with its current line number and explains what
each line does.

The app is a crypto toolbox with **four pages** (Home, Text, File, About) in a
sidebar layout. Text and File share one widget builder but behave differently, and
that builder now supports **three categories**: Classical ciphers, Modern AEAD
encryption (password-based), and Hash algorithms.

## 1. Orientation — the files and the build wiring

| File | Lines | Role |
|---|---|---|
| `src/main.zig` | 47 | Boot: Qt init, fonts, theme, window, then hand off to pages |
| `src/sidebar.zig` | 123 | The left nav column + `PageIndex` enum + theme button |
| `src/theme.zig` | 89 | Dark/light toggle, persisted via `QSettings` |
| `src/style.zig` | 2 | Embeds `src/themes/ayu_dark.qss` / `ayu_light.qss` |
| `src/pages.zig` | 1018 | All four pages, the shared form builder, all handlers |
| `src/root.zig` | 2 | Library entry: re-exports `cipher.zig` + `modern.zig` |
| `src/cipher.zig` | — | 11 classical ciphers (the `oh_my_crypto.cipher` module) |
| `src/modern.zig` | — | AEAD encryption, KDFs, hashes (the `oh_my_crypto.modern` module) |

`build.zig` wires four modules into the executable:

| Import name | Source | Used for |
|---|---|---|
| `oh_my_crypto` | `src/root.zig` | `ciphers` (classical) + `modern` (AEAD/hash) |
| `assets` | `assets/fonts.zig` | embedded `Rubik` TTF files |
| `config` | `b.addOptions` from `build.zig.zon` | `full_name`, `version`, `descrption`, `license` |
| `libqt6zig` | external Zig package | the Qt6 bindings |

`config` is not a file — it is an options module built from `build.zig.zon`
(build.zig:93–98). That is why the About page can show `config.version` without
hard-coding anything.

Everything you need to know to read any Qt file in this repo: **find the
constructor, find the `SetObjectName`, find the `OnXxx` connection.** Those three
lines tell you what a widget is, how it looks, and what it does when touched.

---

## 2. `main.zig` — boot — lines 1–47

### 2.1 Imports — lines 1–12

```zig
const std = @import("std");                    // main.zig:1
const qt6 = @import("libqt6zig");              // main.zig:2
const pages = @import("pages.zig");            // main.zig:3
const theme = @import("theme.zig");            // main.zig:4
const fonts = @import("assets");               // main.zig:5

const QApplication = qt6.QApplication;         // main.zig:7
const QWidget = qt6.QWidget;                   // main.zig:8
const QMainWindow = qt6.QMainWindow;           // main.zig:9
const QHBoxLayout = qt6.QHBoxLayout;           // main.zig:10
const QFont = qt6.QFont;                       // main.zig:11
const QFontDatabase = qt6.QFontDatabase;       // main.zig:12
```

Four imports, but only Qt classes that **main** itself touches. Everything page
related lives in `pages.zig`; everything theme related in `theme.zig`.

### 2.2 The entry point — lines 14–20

```zig
pub fn main(init: std.process.Init) !void {    // main.zig:14
    const argv = try qt6.init(init.gpa, init.minimal.args);  // main.zig:15
    defer qt6.deinit(init.gpa, argv);          // main.zig:16
    var argc: i32 = @intCast(argv.len);        // main.zig:17

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);  // main.zig:19
    defer qapp.Delete();                       // main.zig:20
```

`qt6.init` translates Zig's arg vector into Qt's `argc/argv` form and hands back an
allocated copy. `defer` runs the reverse at exit, so the process cleans up after
itself. The `QApplication` must exist before *any* widget — it owns the event loop
and the global state Qt needs.

### 2.3 Fonts — lines 22–24

```zig
    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik));          // main.zig:22
    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik_italic));   // main.zig:23
    QApplication.SetFont(QFont.New6("Rubik", 12));                                  // main.zig:24
```

`assets/fonts.zig` embeds the TTFs as byte arrays (`@embedFile`). Registering them
with `AddApplicationFontFromData` makes "Rubik" a usable family; the `SetFont` call
then makes it the **default** family at 12pt. One call and every widget inherits it.

### 2.4 Theme — line 26

```zig
    theme.init(init.gpa, qapp);                // main.zig:26
```

Loads the saved (or system) theme and applies its stylesheet. Full tour in §4.

### 2.5 The window — lines 28–32

```zig
    const win = QMainWindow.New2();            // main.zig:28
    defer win.Delete();                        // main.zig:29
    win.SetWindowTitle("Oh My Crypto");        // main.zig:30
    win.SetMinimumSize2(820, 600);             // main.zig:31
    win.Resize(1040, 700);                     // main.zig:32
```

`New2` = default constructor. Minimum size keeps the layout usable; `Resize` picks
the launch size. Small, but note it: `SetMinimumSize2` prevents the sidebar + pages
from collapsing on tiny screens.

### 2.6 Root layout — lines 34–39

```zig
    const root = QWidget.New2();               // main.zig:34
    const root_box = QHBoxLayout.New(root);    // main.zig:35
    root_box.SetContentsMargins(0, 0, 0, 0);   // main.zig:36
    root_box.SetSpacing(0);                    // main.zig:37

    pages.buildUi(init.gpa, init.io, win, root_box);  // main.zig:39
```

A zero-margin horizontal box is the whole chrome. `buildUi` receives the allocator,
the std `Io` handle (for file IO later), the window, and this root box — then builds
everything into it. All the work from here on is `pages.zig`.

### 2.7 Show and run — lines 41–46

```zig
    win.SetCentralWidget(root);                // main.zig:41
    win.Show();                                // main.zig:42

    _ = QApplication.Exec();                   // main.zig:44

    try std.Io.File.stdout().writeStreamingAll(init.io, "OK!\n");  // main.zig:46
```

`SetCentralWidget` — the Qt way to say "this widget fills the window". `Exec()`
blocks forever, pumping events until the window closes. The `OK!` line only runs on
clean shutdown (it doubles as a smoke-test signal in scripts).

---

## 3. `sidebar.zig` — navigation — lines 1–123

### 3.1 Imports and the `PageIndex` enum — lines 1–20

```zig
const std = @import("std");                    // sidebar.zig:1
const config = @import("config");              // sidebar.zig:2
const qt6 = @import("libqt6zig");              // sidebar.zig:3
const theme = @import("theme.zig");            // sidebar.zig:4
...
pub const PageIndex = enum(i32) {              // sidebar.zig:13
    home = 0,                                  // sidebar.zig:14
    text = 1,                                  // sidebar.zig:15
    file = 2,                                  // sidebar.zig:16
    about = 3,                                 // sidebar.zig:17
};
```

`PageIndex` maps page → slot number in the stacked widget. It is `pub` because
`pages.zig` imports it too — the sidebar *moves* the stack, pages *fill* it, and both
must agree on numbering.

### 3.2 State — lines 22–27

```zig
var stack: QStackedWidget = undefined;         // sidebar.zig:22

var nav_home: QPushButton = undefined;         // sidebar.zig:24
var nav_text: QPushButton = undefined;         // sidebar.zig:25
var nav_file: QPushButton = undefined;         // sidebar.zig:26
var nav_about: QPushButton = undefined;        // sidebar.zig:27
```

File-scope globals, set during `build`. Storing the nav buttons lets `selectNav`
update their checked state without hunting through the layout.

### 3.3 `init` — lines 29–31

```zig
pub fn init(s: QStackedWidget) void {          // sidebar.zig:29
    stack = s;                                 // sidebar.zig:30
}
```

`pages.buildUi` creates the stack *first*, then hands it to the sidebar. Split
init/build: the sidebar holds a pointer it didn't create. That is the cross-module
handshake at the top of `buildUi` (pages.zig:138–140).

### 3.4 `build` — lines 33–80

```zig
pub fn build(root_box: QHBoxLayout) void {     // sidebar.zig:33
    const sidebar = QWidget.New2();            // sidebar.zig:34
    sidebar.SetObjectName("sidebar");          // sidebar.zig:35
    sidebar.SetFixedWidth(200);                // sidebar.zig:36
    const v = QBoxLayout.New2(top_to_bottom, sidebar);  // sidebar.zig:37
    v.SetContentsMargins(16, 28, 16, 20);      // sidebar.zig:38
    v.SetSpacing(4);                           // sidebar.zig:39
```

Fixed 200px column; `SetObjectName("sidebar")` points the QSS at it (the dark
`#sidebar` background is painted purely by the stylesheet).

**Brand.** Lines 41–49:

```zig
    const brand = QLabel.New5(config.full_name, sidebar);  // sidebar.zig:41
    brand.SetObjectName("brand");              // sidebar.zig:42
    v.AddWidget2(brand, 0);                    // sidebar.zig:43

    const tagline = QLabel.New5("ciphers & hashes", sidebar);  // sidebar.zig:45
    tagline.SetObjectName("brandTag");         // sidebar.zig:46
    v.AddWidget2(tagline, 0);                  // sidebar.zig:47

    v.AddSpacing(28);                          // sidebar.zig:49
```

App name + tagline at the top, then a gap before the nav buttons.

**Nav buttons.** Lines 51–65:

```zig
    nav_home = newNav(sidebar, "Home");        // sidebar.zig:51
    nav_home.OnClicked(onNavHome);             // sidebar.zig:52
    v.AddWidget2(nav_home, 0);                 // sidebar.zig:53
    ...
    nav_about = newNav(sidebar, "About");      // sidebar.zig:63
    nav_about.OnClicked(onNavAbout);           // sidebar.zig:64
    v.AddWidget2(nav_about, 0);                // sidebar.zig:65
```

Four identical patterns: build via `newNav`, connect a handler, add to the layout.

**Footer.** Lines 67–79:

```zig
    v.AddStretch();                            // sidebar.zig:67

    const theme_btn = QPushButton.New5(theme.label(), sidebar);  // sidebar.zig:69
    theme_btn.SetObjectName("themeBtn");       // sidebar.zig:70
    theme_btn.OnClicked(theme.onButtonClicked);  // sidebar.zig:71
    theme.attachButton(theme_btn);             // sidebar.zig:72
    v.AddWidget2(theme_btn, 0);                // sidebar.zig:73

    const version = QLabel.New5("v" ++ config.version, sidebar);  // sidebar.zig:75
    version.SetObjectName("version");          // sidebar.zig:76
    v.AddWidget2(version, 0);                  // sidebar.zig:77

    root_box.AddWidget2(sidebar, 0);           // sidebar.zig:79
```

`AddStretch` pushes everything after it to the bottom: the theme toggle and version
stamp. The theme button is owned by `sidebar` but *managed* by `theme` — it gets a
callback (`onButtonClicked`) and a stored reference (`attachButton`) so the theme
module can relabel it after a switch.

### 3.5 `newNav` — lines 82–88

```zig
fn newNav(parent: QWidget, text: []const u8) QPushButton {  // sidebar.zig:82
    const b = QPushButton.New5(text, parent);  // sidebar.zig:83
    b.SetObjectName("navBtn");                 // sidebar.zig:84
    b.SetCheckable(true);                      // sidebar.zig:85
    b.SetFixedHeight(40);                      // sidebar.zig:86
    return b;
}
```

Every nav button is checkable — that is what makes the active page's button appear
"pressed". The QSS `#navBtn:checked` rule colors it.

### 3.6 `selectNav` + `selectHome` — lines 90–99

```zig
fn selectNav(active: *const QPushButton) void {  // sidebar.zig:90
    nav_home.SetChecked(nav_home.ptr == active.ptr);  // sidebar.zig:91
    nav_text.SetChecked(nav_text.ptr == active.ptr);  // sidebar.zig:92
    nav_file.SetChecked(nav_file.ptr == active.ptr);  // sidebar.zig:93
    nav_about.SetChecked(nav_about.ptr == active.ptr);  // sidebar.zig:94
}

pub fn selectHome() void {                     // sidebar.zig:97
    selectNav(&nav_home);                      // sidebar.zig:98
}
```

Check exactly one: `.ptr` identity comparison against the active button. `selectHome`
is called by `pages.buildUi` after all pages are registered, so the app boots on
Home with Home highlighted.

### 3.7 Nav handlers — lines 101–123

```zig
fn onNavHome(self: QPushButton) callconv(.c) void {  // sidebar.zig:101
    _ = self;                                    // sidebar.zig:102
    selectNav(&nav_home);                        // sidebar.zig:103
    stack.SetCurrentIndex(@intFromEnum(PageIndex.home));  // sidebar.zig:104
}
```

All four handlers have the same two-step shape: fix the button highlight, then flip
the stacked widget to the matching slot. `@intFromEnum` turns the Zig enum into the
slot number Qt expects. Every Qt callback here is `callconv(.c)` — the binding layer
uses the C ABI.

---

## 4. `theme.zig` — dark/light toggle — lines 1–89

### 4.1 Imports and state — lines 1–22

```zig
const style = @import("style.zig");            // theme.zig:3
...
pub const Theme = enum { dark, light };        // theme.zig:11

const settings_org = "oh-my-crypto";           // theme.zig:13
const settings_app = "omc";                    // theme.zig:14
const settings_format: i32 = 1; // QSettings.IniFormat  // theme.zig:15
const settings_scope: i32 = 0; // QSettings.UserScope   // theme.zig:16
const color_scheme_light: i32 = 1;             // theme.zig:17
const color_scheme_dark: i32 = 2;              // theme.zig:18

var current_theme: Theme = .dark;              // theme.zig:20
var qapp_ref: QApplication = undefined;        // theme.zig:21
var theme_btn: QPushButton = undefined;        // theme.zig:22
```

`QSettings` persistence needs an org + app key; the numeric format/scope constants
map to Qt's `QSettings.IniFormat` and `UserScope`. `color_scheme_*` are the values
`QStyleHints.ColorScheme()` returns on Linux (Qt 6.5+).

### 4.2 `init` — lines 24–28

```zig
pub fn init(gpa: std.mem.Allocator, qapp: QApplication) void {  // theme.zig:24
    qapp_ref = qapp;                             // theme.zig:25
    current_theme = loadSavedTheme(gpa) orelse detectSystemTheme();  // theme.zig:26
    qapp.SetStyleSheet(themeQss());              // theme.zig:27
}
```

Decision order: **saved preference wins**, otherwise follow the OS theme, otherwise
dark. The chosen theme's QSS is applied to the whole app via `SetStyleSheet`.

### 4.3 The toggle — lines 30–45

```zig
pub fn attachButton(btn: QPushButton) void {     // theme.zig:30
    theme_btn = btn;                             // theme.zig:31
    theme_btn.SetText(label());                  // theme.zig:32
}

pub fn onButtonClicked(self: QPushButton) callconv(.c) void {  // theme.zig:35
    _ = self;
    applyTheme(if (current_theme == .dark) .light else .dark);  // theme.zig:37
}

pub fn label() []const u8 {                      // theme.zig:40
    return switch (current_theme) {
        .dark => "Switch to Light",              // theme.zig:42
        .light => "Switch to Dark",              // theme.zig:43
    };
}
```

The button text *describes the action you take*, not the current state ("Switch to
Light" while dark). `attachButton` is called by the sidebar (sidebar.zig:72) so the
label can be refreshed after every switch.

### 4.4 QSS selection — lines 47–60

```zig
fn themeQss() []const u8 {                       // theme.zig:47
    return switch (current_theme) {
        .dark => style.dark,                     // theme.zig:49
        .light => style.light,                   // theme.zig:50
    };
}

fn detectSystemTheme() Theme {                   // theme.zig:54
    return switch (QGuiApplication.StyleHints().ColorScheme()) {  // theme.zig:55
        color_scheme_dark => .dark,              // theme.zig:56
        color_scheme_light => .light,            // theme.zig:57
        else => .dark,                           // theme.zig:58
    };
}
```

`style.dark`/`style.light` are just `@embedFile` strings (style.zig:1–2) — swapping
the theme is literally swapping which big string gets handed to Qt.

### 4.5 Persistence — lines 62–89

```zig
fn newSettings() QSettings {                     // theme.zig:62
    return QSettings.New11(settings_format, settings_scope, settings_org, settings_app);  // theme.zig:63
}

fn loadSavedTheme(gpa: std.mem.Allocator) ?Theme {  // theme.zig:66
    const settings = newSettings();              // theme.zig:67
    defer settings.Delete();                     // theme.zig:68

    const v = settings.Value("theme", QVariant.New24(""));  // theme.zig:70
    const saved = v.ToString(gpa);               // theme.zig:71
    defer gpa.free(saved);                       // theme.zig:72

    if (std.mem.eql(u8, saved, "dark")) return .dark;  // theme.zig:74
    if (std.mem.eql(u8, saved, "light")) return .light;  // theme.zig:75
    return null;                                 // theme.zig:76
}

fn applyTheme(t: Theme) void {                   // theme.zig:79
    if (t == current_theme) return;              // theme.zig:80
    current_theme = t;                           // theme.zig:81
    qapp_ref.SetStyleSheet(themeQss());          // theme.zig:82
    theme_btn.SetText(label());                  // theme.zig:83

    const settings = newSettings();              // theme.zig:85
    defer settings.Delete();
    settings.SetValue("theme", QVariant.New24(if (t == .dark) "dark" else "light"));  // theme.zig:87
    settings.Sync();                             // theme.zig:88
}
```

`loadSavedTheme` reads a string key and returns `null` when it is missing/unknown —
the caller falls back to the OS. `applyTheme` re-points the QSS, re-labels the
button, and writes the choice to disk (`Sync` flushes). The string round-trips
through `QVariant` because that is the type `QSettings` stores.

---

## 5. `pages.zig` — the whole UI — lines 1–1018

### 5.0 Imports, names, state — lines 1–131

```zig
const std = @import("std");                      // pages.zig:1
const config = @import("config");                // pages.zig:2
const qt6 = @import("libqt6zig");                // pages.zig:3
const ciphers = @import("oh_my_crypto").cipher;  // pages.zig:4
const modern = @import("oh_my_crypto").modern;   // pages.zig:5
const sidebar = @import("sidebar.zig");          // pages.zig:6
```

Four dependency roots: std, the build-time config, Qt, and the app's own crypto
library (`oh_my_crypto`, which is `src/root.zig` → `cipher` + `modern`).

**Qt aliases.** Lines 8–26 pull in the ~20 Qt classes this file touches — everything
from `QWidget` to `QGraphicsDropShadowEffect`. The C cipher types come next:

```zig
const Cipher = ciphers.Cipher;                   // pages.zig:28
const Caesar = ciphers.Caesar;                   // pages.zig:29
const Multiplicative = ciphers.Multiplicative;   // pages.zig:30
const Affine = ciphers.Affine;                   // pages.zig:31
const Autokey = ciphers.Autokey;                 // pages.zig:32
const Viegener = ciphers.Viegener;               // pages.zig:33
const Zigzag = ciphers.Zigzag;                   // pages.zig:34
const Atbash = ciphers.Atbash;                   // pages.zig:35
const Rot13 = ciphers.Rot13;                     // pages.zig:36
const Beaufort = ciphers.Beaufort;               // pages.zig:37
const ColumnarTransposition = ciphers.ColumnarTransposition;  // pages.zig:38
const Bifid = ciphers.Bifid;                     // pages.zig:39
```

Eleven classical ciphers. Note the deliberate misspelling `Viegener` — that is the
struct's name in `cipher.zig`; the *display* name is "Vigenere" (classical_names,
line 55). The UI-facing string and the implementation identifier are separate.

```zig
const align_center: i32 = 132;                   // pages.zig:41
pub const top_to_bottom: i32 = 2;                // pages.zig:42
```

Two Qt enum values spelled out as bare ints. `132` is `Qt.AlignCenter`, `2` is
`QBoxLayout.Direction.TopToBottom`. `top_to_bottom` is `pub` — `sidebar.zig` needs
the same constant for its own column.

**The `Mode` enum.** Lines 46–49:

```zig
const Mode = enum {
    encrypt,
    decrypt,
};
```

Used by the shared `execute`/`doCipher` pipeline so Encrypt and Decrypt are one code
path with a flag. `onTextHash` reuses `.encrypt` — hashing has no direction.

**The algorithm name tables.** Lines 51–96:

```zig
const classical_names = [_][]const u8{           // pages.zig:51
    "Caesar",                                    // pages.zig:52
    ...
    "Bifid",                                     // pages.zig:62
};

const modern_names = [_][]const u8{              // pages.zig:65
    "XChaCha20-Poly1305",                        // pages.zig:66
    "ChaCha20-Poly1305",                         // pages.zig:67
    "AES-256-GCM",                               // pages.zig:68
    "AES-128-GCM",                               // pages.zig:69
    "AES-256-GCM-SIV",                           // pages.zig:70
    "AES-128-GCM-SIV",                           // pages.zig:71
    "AEGIS-256",                                 // pages.zig:72
    "AEGIS-128L",                                // pages.zig:73
    "XSalsa20-Poly1305",                         // pages.zig:74
    "XChaCha12-Poly1305",                        // pages.zig:75
    "ChaCha12-Poly1305",                         // pages.zig:76
};

const hash_names = [_][]const u8{                // pages.zig:79
    "SHA-256", ... "BLAKE2b-512",                // pages.zig:80–95
};
```

Array order **is** the combo's index order. `updateCipherFields`/`doHash`/`doModern`
all switch on that index, so the position in these tables is the contract between UI
and engine. 11 + 11 + 16 = 38 algorithms.

**The `Form` struct.** Lines 98–118:

```zig
const Form = struct {
    category: QComboBox,                         // pages.zig:99
    combo: QComboBox,                            // pages.zig:100
    keyword_edit: QLineEdit,                     // pages.zig:101
    password_edit: QLineEdit,                    // pages.zig:102
    kdf_combo: QComboBox,                        // pages.zig:103
    num1: QSpinBox,                              // pages.zig:104
    num2: QSpinBox,                              // pages.zig:105
    num1_label: QLabel,                          // pages.zig:106
    num2_label: QLabel,                          // pages.zig:107
    input: QPlainTextEdit,                       // pages.zig:108
    output: QPlainTextEdit,                      // pages.zig:109
    status: QLabel,                              // pages.zig:110
    input_count: QLabel,                         // pages.zig:111
    output_count: QLabel,                        // pages.zig:112
    copy_btn: QPushButton,                       // pages.zig:113
    swap_btn: QPushButton,                       // pages.zig:114
    enc_btn: QPushButton = undefined,            // pages.zig:115
    dec_btn: QPushButton = undefined,            // pages.zig:116
    hash_btn: QPushButton = undefined,           // pages.zig:117
};
```

A `Form` is a named bundle of every widget one processing page needs. The three
action buttons have default values because they are wired up **after** `buildCipherForm`
returns (by `buildText`/`buildFile`) — Zig lets them be `undefined` until then.

**Globals.** Lines 120–131:

```zig
var io: std.Io = undefined;                      // pages.zig:120
var gpa: std.mem.Allocator = undefined;          // pages.zig:121
var main_win: QMainWindow = undefined;           // pages.zig:122
var stack: QStackedWidget = undefined;           // pages.zig:123

var text_form: Form = undefined;                 // pages.zig:125
var file_form: Form = undefined;                 // pages.zig:126
var file_path_label: QLabel = undefined;         // pages.zig:127

var title_effect: QGraphicsDropShadowEffect = undefined;  // pages.zig:129
var title_timer: QTimer = undefined;             // pages.zig:130
var glow_phase: f64 = 0;                         // pages.zig:131
```

Module-level state, the Qt GUI equivalent of globals (the callback ABI needs
addresses that outlive the builder). `text_form`/`file_form` are the anchor pair the
`.ptr` dispatchers compare against (see §5.18).

### 5.1 `buildUi` — lines 133–148

```zig
pub fn buildUi(g: std.mem.Allocator, app_io: std.Io, win: QMainWindow, root_box: QHBoxLayout) void {  // pages.zig:133
    gpa = g;                                     // pages.zig:134
    io = app_io;                                 // pages.zig:135
    main_win = win;                              // pages.zig:136

    stack = QStackedWidget.New2();               // pages.zig:138
    sidebar.init(stack);                         // pages.zig:139
    sidebar.build(root_box);                     // pages.zig:140
    root_box.AddWidget2(stack, 1);               // pages.zig:141

    buildHome();                                 // pages.zig:143
    buildText();                                 // pages.zig:144
    buildFile();                                 // pages.zig:145
    buildAbout();                                // pages.zig:146
    sidebar.selectHome();                        // pages.zig:147
}
```

The choreography in five steps:

1. Stash the allocator/io/window in globals for later handlers.
2. Create the `QStackedWidget` — the page container.
3. Build the sidebar into `root_box`, giving it the stack to control.
4. Register the four pages in order (Home, Text, File, About).
5. `sidebar.selectHome()` — boot on Home with the Home button lit.

Page → slot mapping comes from *registration order*; the sidebar's `PageIndex` must
match. This is the one hand-written contract to keep straight when adding a page.

### 5.2 `buildHome` — lines 150–237

**Page setup.** Lines 150–157:

```zig
fn buildHome() void {                            // pages.zig:150
    const page = QWidget.New2();                 // pages.zig:151
    page.SetObjectName("pageHome");              // pages.zig:152
    const v = QBoxLayout.New2(top_to_bottom, page);  // pages.zig:153
    v.SetContentsMargins(48, 64, 48, 48);        // pages.zig:154
    v.SetSpacing(16);                            // pages.zig:155

    v.AddStretch();                              // pages.zig:157
```

Every page: a `QWidget` with an object name for QSS, a top-to-bottom box, generous
margins. The leading `AddStretch` pushes the content into the vertical middle.

**Title + glow.** Lines 159–173:

```zig
    const title = QLabel.New5(config.full_name, page);  // pages.zig:159
    title.SetObjectName("title");                // pages.zig:160
    title.SetAlignment(align_center);            // pages.zig:161
    v.AddWidget2(title, 0);                      // pages.zig:162

    title_effect = QGraphicsDropShadowEffect.New2(page);  // pages.zig:164
    title_effect.SetColor(QColor.New5(0xe6, 0xb4, 0x50));  // pages.zig:165
    title_effect.SetOffset3(0);                  // pages.zig:166
    title_effect.SetBlurRadius(50);              // pages.zig:167
    title.SetGraphicsEffect(title_effect);       // pages.zig:168

    title_timer = QTimer.New2(page);             // pages.zig:170
    title_timer.SetInterval(80);                 // pages.zig:171
    title_timer.OnTimeout(onTitleGlow);          // pages.zig:172
    title_timer.Start(80);                       // pages.zig:173
```

The animated glow: a gold `QGraphicsDropShadowEffect` on the title, driven by a
timer that fires every 80ms and calls `onTitleGlow` (§5.12). `SetBlurRadius(50)` is
the starting static state; the callback will override it.

**Subtitle, divider, chips.** Lines 175–217:

```zig
    const subtitle = QLabel.New5(
        "Encrypt, decrypt and hash text with classical and modern algorithms",  // pages.zig:175–178
        page,
    );
    subtitle.SetObjectName("subtitle");          // pages.zig:179
    subtitle.SetAlignment(align_center);         // pages.zig:180
    v.AddWidget2(subtitle, 0);                   // pages.zig:181

    const divider = QLabel.New5("", page);       // pages.zig:183
    divider.SetObjectName("divider");            // pages.zig:184
    divider.SetFixedWidth(96);                   // pages.zig:185
    divider.SetFixedHeight(2);                   // pages.zig:186
    v.AddWidget3(divider, 0, align_center);      // pages.zig:187

    v.AddSpacing(36);                            // pages.zig:189

    const chips_host = QWidget.New2();           // pages.zig:191
    chips_host.SetObjectName("chipsHost");       // pages.zig:192
    const chips = QGridLayout.New(chips_host);   // pages.zig:193
    chips.SetHorizontalSpacing(12);              // pages.zig:194
    chips.SetVerticalSpacing(12);                // pages.zig:195
```

The divider is a *2px-tall empty label* — fixed width+height turns a text widget
into a rule line. `AddWidget3` is the overload that takes an alignment.

The chips grid is a `QGridLayout` filled by a `for` loop (lines 196–216):

```zig
    const ciphers_list = [_][]const u8{
        "Caesar", ..., "Bifid",                  // pages.zig:196–208
    };
    for (ciphers_list, 0..) |name, i| {          // pages.zig:209
        const row: i32 = @intCast(i / 3);        // pages.zig:210
        const col: i32 = @intCast(i % 3);        // pages.zig:211
        const chip = QLabel.New5(name, chips_host);  // pages.zig:212
        chip.SetObjectName("chip");              // pages.zig:213
        chip.SetAlignment(align_center);         // pages.zig:214
        chips.AddWidget2(chip, row, col);        // pages.zig:215
    }
    v.AddWidget3(chips_host, 0, align_center);   // pages.zig:217
```

11 names → row = `i / 3`, col = `i % 3`, so the grid is 3 columns wide. All chips
share one object name — one QSS rule styles all 11.

**Note + footer.** Lines 219–236:

```zig
    const note = QLabel.New5(
        "Classical ciphers and modern AEAD encryption with password key derivation\n(not for real data).",  // pages.zig:221–224
        page,
    );
    note.SetObjectName("note");                  // pages.zig:225
    note.SetAlignment(align_center);             // pages.zig:226
    v.AddWidget2(note, 0);                       // pages.zig:227

    v.AddStretch();                              // pages.zig:229

    const footer = QLabel.New5("Educational tool", page);  // pages.zig:231
    footer.SetObjectName("footer");              // pages.zig:232
    footer.SetAlignment(align_center);           // pages.zig:233
    v.AddWidget2(footer, 0);                     // pages.zig:234

    _ = stack.AddWidget(page);                   // pages.zig:236
}
```

The trailing `AddStretch` balances the leading one (content vertically centered).
The final `_ = stack.AddWidget(page)` is what *registers* the page and fixes its
slot number — that is why this is the last line of every `buildXxx`.

### 5.3 `buildText` — lines 239–282

```zig
fn buildText() void {                            // pages.zig:239
    const page = QWidget.New2();                 // pages.zig:240
    page.SetObjectName("pageText");              // pages.zig:241
    const v = QBoxLayout.New2(top_to_bottom, page);  // pages.zig:242
    v.SetContentsMargins(28, 24, 28, 24);        // pages.zig:243
    v.SetSpacing(12);                            // pages.zig:244

    const heading = QLabel.New5("Encrypt / Decrypt Text", page);  // pages.zig:246
    heading.SetObjectName("heading");            // pages.zig:247
    v.AddWidget2(heading, 0);                    // pages.zig:248

    const form = buildCipherForm(page, v, true); // pages.zig:250
    text_form = form;                            // pages.zig:251
```

Heading, then the shared form builder with `editable_input = true` (you type into
the Text page). The returned `Form` is stored as the global `text_form`.

**Action buttons.** Lines 253–279:

```zig
    const btns = QHBoxLayout.New(page);          // pages.zig:253
    const btn_enc = QPushButton.New5("Encrypt", page);  // pages.zig:254
    btn_enc.SetObjectName("primaryBtn");         // pages.zig:255
    btn_enc.OnClicked(onTextEncrypt);            // pages.zig:256
    btns.AddWidget2(btn_enc, 1);                 // pages.zig:257

    const btn_dec = QPushButton.New5("Decrypt", page);  // pages.zig:259
    btn_dec.SetObjectName("secondaryBtn");       // pages.zig:260
    btn_dec.OnClicked(onTextDecrypt);            // pages.zig:261
    btns.AddWidget2(btn_dec, 1);                 // pages.zig:262

    const btn_hash = QPushButton.New5("Hash", page);  // pages.zig:264
    btn_hash.SetObjectName("primaryBtn");        // pages.zig:265
    btn_hash.OnClicked(onTextHash);              // pages.zig:266
    btn_hash.SetVisible(false);                  // pages.zig:267
    btns.AddWidget2(btn_hash, 1);                // pages.zig:268

    const btn_clear = QPushButton.New5("Clear", page);  // pages.zig:270
    btn_clear.SetObjectName("ghostBtn");         // pages.zig:271
    btn_clear.OnClicked(onTextClear);            // pages.zig:272
    btns.AddWidget2(btn_clear, 0);               // pages.zig:273
    v.AddLayout2(btns, 0);                       // pages.zig:274

    text_form.enc_btn = btn_enc;                 // pages.zig:276
    text_form.dec_btn = btn_dec;                 // pages.zig:277
    text_form.hash_btn = btn_hash;               // pages.zig:278
    updateActionButtons(text_form);              // pages.zig:279
```

Four buttons in a row. The **Hash** button starts hidden — it only appears when the
user switches the category combo to "Hash" (`updateActionButtons`, §5.10). The three
action buttons are stored back into the form *after* the fact, completing the
`undefined` fields from §5.0.

```zig
    _ = stack.AddWidget(page);                   // pages.zig:281
}
```

### 5.4 `buildFile` — lines 284–342

```zig
fn buildFile() void {                            // pages.zig:284
    const page = QWidget.New2();                 // pages.zig:285
    page.SetObjectName("pageFile");              // pages.zig:286
    const v = QBoxLayout.New2(top_to_bottom, page);  // pages.zig:287
    v.SetContentsMargins(28, 24, 28, 24);        // pages.zig:288
    v.SetSpacing(12);                            // pages.zig:289

    const heading = QLabel.New5("Process Text File", page);  // pages.zig:291
    heading.SetObjectName("heading");            // pages.zig:292
    v.AddWidget2(heading, 0);                    // pages.zig:293

    const open_row = QHBoxLayout.New(page);      // pages.zig:295
    const btn_open = QPushButton.New5("Open Text File...", page);  // pages.zig:296
    btn_open.SetObjectName("primaryBtn");        // pages.zig:297
    btn_open.OnClicked(onFileOpen);              // pages.zig:298
    open_row.AddWidget2(btn_open, 0);            // pages.zig:299

    file_path_label = QLabel.New5("No file selected", page);  // pages.zig:301
    file_path_label.SetObjectName("status");     // pages.zig:302
    file_path_label.SetWordWrap(true);           // pages.zig:303
    open_row.AddWidget2(file_path_label, 1);     // pages.zig:304
    v.AddLayout2(open_row, 0);                   // pages.zig:305

    const form = buildCipherForm(page, v, false);  // pages.zig:307
    file_form = form;                            // pages.zig:308
```

Same skeleton, two differences: an Open row up top, and `buildCipherForm` gets
`editable_input = false` (the input pane is read-only; file content comes from disk).
The path label is named `"status"` deliberately — it reuses the status-line QSS look.

**Buttons.** Lines 310–339:

```zig
    const btns = QHBoxLayout.New(page);          // pages.zig:310
    const btn_enc = QPushButton.New5("Encrypt", page);  // pages.zig:311
    btn_enc.SetObjectName("primaryBtn");
    btn_enc.OnClicked(onFileEncrypt);            // pages.zig:313
    btns.AddWidget2(btn_enc, 1);                 // pages.zig:314

    const btn_dec = QPushButton.New5("Decrypt", page);  // pages.zig:316
    btn_dec.SetObjectName("secondaryBtn");
    btn_dec.OnClicked(onFileDecrypt);            // pages.zig:318
    btns.AddWidget2(btn_dec, 1);                 // pages.zig:319

    const btn_hash = QPushButton.New5("Hash", page);  // pages.zig:321
    btn_hash.SetObjectName("primaryBtn");
    btn_hash.OnClicked(onFileHash);              // pages.zig:323
    btn_hash.SetVisible(false);                  // pages.zig:324
    btns.AddWidget2(btn_hash, 1);                // pages.zig:325
    v.AddLayout2(btns, 0);                       // pages.zig:326

    file_form.enc_btn = btn_enc;                 // pages.zig:328
    file_form.dec_btn = btn_dec;                 // pages.zig:329
    file_form.hash_btn = btn_hash;               // pages.zig:330
    updateActionButtons(file_form);              // pages.zig:331

    const save_row = QHBoxLayout.New(page);      // pages.zig:333
    const btn_save = QPushButton.New5("Save Result...", page);  // pages.zig:334
    btn_save.SetObjectName("primaryBtn");
    btn_save.OnClicked(onFileSave);              // pages.zig:336
    save_row.AddWidget2(btn_save, 0);            // pages.zig:337
    save_row.AddStretch();                       // pages.zig:338
    v.AddLayout2(save_row, 0);                   // pages.zig:339

    _ = stack.AddWidget(page);                   // pages.zig:341
}
```

Mirrors `buildText` but routes to the File handlers and adds a Save button below.

### 5.5 `buildAbout` — lines 344–407

```zig
fn buildAbout() void {                           // pages.zig:344
    const page = QWidget.New2();                 // pages.zig:345
    page.SetObjectName("pageAbout");             // pages.zig:346
    const v = QBoxLayout.New2(top_to_bottom, page);  // pages.zig:347
    v.SetContentsMargins(28, 24, 28, 24);        // pages.zig:348
    v.SetSpacing(12);                            // pages.zig:349

    const heading = QLabel.New5("About", page);  // pages.zig:351
    heading.SetObjectName("heading");
    v.AddWidget2(heading, 0);                    // pages.zig:353

    v.AddSpacing(4);                             // pages.zig:355
```

Same page recipe, then a series of `newPanel` sections. First, the intro panel with
the version badge (lines 357–368):

```zig
    const p_intro = newPanel(page, v, config.full_name, 0);  // pages.zig:357
    const badge = QLabel.New5("v" ++ config.version, p_intro.panel);  // pages.zig:358
    badge.SetObjectName("versionBadge");         // pages.zig:359
    p_intro.header.AddWidget2(badge, 0);         // pages.zig:360

    const intro = QLabel.New5(
        config.descrption,                       // pages.zig:362–365
        p_intro.panel,
    );
    intro.SetObjectName("about");                // pages.zig:366
    intro.SetWordWrap(true);                     // pages.zig:367
    p_intro.v.AddWidget2(intro, 0);              // pages.zig:368
```

Here is the first payoff of `config`: the panel *title* and the badge text come from
`build.zig.zon`, so bumping the version is one line in the ZON file. The badge is
dropped into the panel's **header** row (right of the title, after the stretch).

**Features list.** Lines 370–384:

```zig
    const p_feat = newPanel(page, v, "Features", 0);  // pages.zig:370
    const bullets = [_][]const u8{               // pages.zig:371
        "•  Eleven classical ciphers: ...",      // pages.zig:372
        "•  Eleven modern AEAD algorithms ...",  // pages.zig:373
        "•  Sixteen hash algorithms: ...",       // pages.zig:374
        "•  Encrypt or decrypt typed text, hash it, or process .txt files",  // pages.zig:375
        "•  Copy results or move them back to the input in one click",  // pages.zig:376
        "•  Live char and word counts with a status line",  // pages.zig:377
    };
    for (bullets) |b| {                          // pages.zig:379
        const line = QLabel.New5(b, p_feat.panel);  // pages.zig:380
        line.SetObjectName("aboutLine");         // pages.zig:381
        line.SetWordWrap(true);
        p_feat.v.AddWidget2(line, 0);            // pages.zig:383
    }
```

A `for` over a compile-time array — same trick as the chips, one object name for all.

**Warning + license panels.** Lines 386–404:

```zig
    const p_warn = newPanel(page, v, "Educational tool", 0);  // pages.zig:386
    const warn = QLabel.New5(
        "These ciphers are trivially breakable ...",  // pages.zig:387–390
        p_warn.panel,
    );
    warn.SetObjectName("aboutLine");
    warn.SetWordWrap(true);
    p_warn.v.AddWidget2(warn, 0);                // pages.zig:393

    const p_lic = newPanel(page, v, "License", 0);  // pages.zig:395
    const lic = QLabel.New5(
        config.license ++ ".\nQt is licensed separately (LGPL/GPL/commercial).",  // pages.zig:396–399
        p_lic.panel,
    );
    lic.SetObjectName("aboutLine");
    lic.SetWordWrap(true);
    p_lic.v.AddWidget2(lic, 0);                  // pages.zig:402

    v.AddStretch();                              // pages.zig:404

    _ = stack.AddWidget(page);                   // pages.zig:406
}
```

`config.license` from the ZON file again. The trailing stretch pins panels to the
top; the stack registration closes the page.

### 5.6 `Panel` + `newPanel` — lines 409–431

```zig
const Panel = struct {
    panel: QWidget,                              // pages.zig:410
    v: QBoxLayout,                               // pages.zig:411
    header: QHBoxLayout,                         // pages.zig:412
};
```

The reusable card: a widget, its main column, and its caption row. Returning all
three lets callers stuff widgets into either the body or the header.

```zig
fn newPanel(page: QWidget, parent_layout: QBoxLayout, title_text: []const u8, stretch: i32) Panel {  // pages.zig:415
    const panel = QWidget.New(page);             // pages.zig:416
    panel.SetObjectName("panel");                // pages.zig:417
    const pv = QBoxLayout.New2(top_to_bottom, panel);  // pages.zig:418
    pv.SetContentsMargins(14, 12, 14, 10);       // pages.zig:419
    pv.SetSpacing(8);                            // pages.zig:420

    const header = QHBoxLayout.New(panel);       // pages.zig:422
    const title = QLabel.New5(title_text, panel);  // pages.zig:423
    title.SetObjectName("panelTitle");           // pages.zig:424
    header.AddWidget2(title, 0);                 // pages.zig:425
    header.AddStretch();                         // pages.zig:426

    pv.AddLayout2(header, 0);                    // pages.zig:428
    parent_layout.AddWidget2(panel, stretch);    // pages.zig:429
    return .{ .panel = panel, .v = pv, .header = header };  // pages.zig:430
}
```

One builder, every card: a `QWidget` named `"panel"`, a title in a header row with
an `AddStretch` (so *anything* added to `.header` lands on the right), and the body
column. The `stretch` param decides if the card expands to fill leftover vertical
space (`1` for Input/Output panels, `0` for fixed-height cards).

### 5.7 `buildCipherForm` — lines 433–568

The heart of the app. One function builds the shared crypto form for both Text and
File. The `editable_input` bool is the only difference between the two.

**Signature + first panel.** Lines 433–440:

```zig
fn buildCipherForm(page: QWidget, parent_layout: QBoxLayout, editable_input: bool) Form {  // pages.zig:433
    const p_cipher = newPanel(page, parent_layout, "Cipher & Key", 0);  // pages.zig:434

    const category = QComboBox.New(p_cipher.panel);  // pages.zig:436
    category.AddItem("Classical");               // pages.zig:437
    category.AddItem("Modern");                  // pages.zig:438
    category.AddItem("Hash");                    // pages.zig:439
    p_cipher.v.AddWidget2(category, 0);          // pages.zig:440
```

The **category combo** is new in this architecture. It is the top-level selector:
Classical (11 ciphers), Modern (11 AEADs), Hash (16 hashes). Its index (0/1/2) drives
every visibility decision downstream.

**The algorithm combo.** Lines 442–446:

```zig
    const combo = QComboBox.New(p_cipher.panel); // pages.zig:442
    for (classical_names) |name| {               // pages.zig:443
        combo.AddItem(name);                     // pages.zig:444
    }
    p_cipher.v.AddWidget2(combo, 0);             // pages.zig:446
```

Starts filled with the classical list. Switching category calls
`repopulateAlgorithmCombo` to replace these items (§5.9).

**The modern row.** Lines 448–464:

```zig
    const modern_row = QHBoxLayout.New(p_cipher.panel);  // pages.zig:448

    const password_edit = QLineEdit.New(p_cipher.panel);  // pages.zig:450
    password_edit.SetPlaceholderText("Password (modern)");  // pages.zig:451
    password_edit.SetEchoMode(qt6.qlineedit_enums.EchoMode.Normal);  // pages.zig:452
    password_edit.SetClearButtonEnabled(true);  // pages.zig:453
    password_edit.SetVisible(false);             // pages.zig:454
    modern_row.AddWidget2(password_edit, 3);     // pages.zig:455

    const kdf_combo = QComboBox.New(p_cipher.panel);  // pages.zig:457
    kdf_combo.AddItem("Argon2id");               // pages.zig:458
    kdf_combo.AddItem("PBKDF2-SHA256");          // pages.zig:459
    kdf_combo.AddItem("scrypt");                 // pages.zig:460
    kdf_combo.SetVisible(false);                 // pages.zig:461
    modern_row.AddWidget2(kdf_combo, 1);         // pages.zig:462

    p_cipher.v.AddLayout2(modern_row, 0);        // pages.zig:464
```

Password field (wide, stretch 3) + KDF chooser (narrow, stretch 1). Both hidden by
default; `updateCipherFields` reveals them only for the Modern category. The echo
mode is set to `Normal` deliberately — see the "no password mask" fix in the commit
log (the earlier build masked it and had to be reverted).

**The classical key row.** Lines 466–495:

```zig
    const key_row = QHBoxLayout.New(p_cipher.panel);  // pages.zig:466

    const keyword_edit = QLineEdit.New(p_cipher.panel);  // pages.zig:468
    keyword_edit.SetPlaceholderText("Keyword (letters only)");  // pages.zig:469
    keyword_edit.SetVisible(false);              // pages.zig:470
    key_row.AddWidget2(keyword_edit, 3);         // pages.zig:471

    const num1_label = QLabel.New5("Shift", p_cipher.panel);  // pages.zig:473
    num1_label.SetObjectName("keyLabel");        // pages.zig:474
    key_row.AddWidget2(num1_label, 0);           // pages.zig:475

    const num1 = QSpinBox.New(p_cipher.panel);   // pages.zig:477
    num1.SetRange(0, 25);                        // pages.zig:478
    num1.SetValue(3);                            // pages.zig:479
    num1.SetFixedHeight(32);                     // pages.zig:480
    key_row.AddWidget2(num1, 1);                 // pages.zig:481

    const num2_label = QLabel.New5("key 2", p_cipher.panel);  // pages.zig:483
    num2_label.SetObjectName("keyLabel");        // pages.zig:484
    num2_label.SetVisible(false);                // pages.zig:485
    key_row.AddWidget2(num2_label, 0);           // pages.zig:486

    const num2 = QSpinBox.New(p_cipher.panel);   // pages.zig:488
    num2.SetRange(0, 25);                        // pages.zig:489
    num2.SetValue(9);                            // pages.zig:490
    num2.SetVisible(false);                      // pages.zig:491
    num2.SetFixedHeight(32);                     // pages.zig:492
    key_row.AddWidget2(num2, 1);                 // pages.zig:493

    p_cipher.v.AddLayout2(key_row, 0);           // pages.zig:495
```

The key row holds **all** classical key inputs: a keyword field, a primary number,
a secondary number. Irrelevant ones start hidden; `updateCipherFields` toggles them.
Stretch weights: keyword `3` (wide), spinboxes `1`. `SetValue(9)` on `num2` is the
default for Affine's `b`; it just starts invisible.

**The scroll area.** Lines 497–506:

```zig
    const scroll_host = QScrollArea.New2();      // pages.zig:497
    scroll_host.SetObjectName("scrollArea");     // pages.zig:498
    scroll_host.SetWidgetResizable(true);        // pages.zig:499

    const scroll_widget = QWidget.New2();        // pages.zig:501
    scroll_widget.SetObjectName("scrollHost");   // pages.zig:502
    const scroll_layout = QBoxLayout.New2(top_to_bottom, scroll_widget);  // pages.zig:503
    scroll_layout.SetContentsMargins(0, 0, 0, 0);// pages.zig:504
    scroll_layout.SetSpacing(8);                 // pages.zig:505
    scroll_host.SetWidget(scroll_widget);        // pages.zig:506
```

A scroll area wraps the Input/Output panels, so a small window can scroll instead of
crushing the text panes. The container widget + its layout is the standard Qt
scroll-pattern: `SetWidgetResizable(true)` makes the inner widget stretch to the
viewport, `SetWidget` installs it.

**Input panel.** Lines 508–516:

```zig
    const p_in = newPanel(scroll_widget, scroll_layout, "Input", 1);  // pages.zig:508
    const input = QPlainTextEdit.New(p_in.panel);  // pages.zig:509
    input.SetPlaceholderText("Type or paste text here...");  // pages.zig:510
    input.SetReadOnly(!editable_input);          // pages.zig:511
    p_in.v.AddWidget2(input, 1);                 // pages.zig:512

    const input_count = QLabel.New5("0 characters", p_in.panel);  // pages.zig:514
    input_count.SetObjectName("countLabel");     // pages.zig:515
    p_in.v.AddWidget2(input_count, 0);           // pages.zig:516
```

`editable_input` drives `SetReadOnly` — the same builder produces an editable Text
page and a read-only File page. The panels live in `scroll_layout`, not
`parent_layout`.

**Output panel.** Lines 518–540:

```zig
    const p_out = newPanel(scroll_widget, scroll_layout, "Output", 1);  // pages.zig:518
    const output = QPlainTextEdit.New(p_out.panel);  // pages.zig:519
    output.SetObjectName("outputPane");          // pages.zig:520
    output.SetReadOnly(true);                    // pages.zig:521
    output.SetPlaceholderText("Result appears here...");  // pages.zig:522
    p_out.v.AddWidget2(output, 1);               // pages.zig:523

    const copy_btn = QPushButton.New5("Copy", p_out.panel);  // pages.zig:525
    copy_btn.SetObjectName("miniBtn");           // pages.zig:526
    copy_btn.OnClicked(onCopy);                  // pages.zig:527
    p_out.header.AddWidget2(copy_btn, 0);        // pages.zig:528

    const swap_btn = QPushButton.New5("To Input", p_out.panel);  // pages.zig:530
    swap_btn.SetObjectName("miniBtn");           // pages.zig:531
    swap_btn.OnClicked(onSwap);                  // pages.zig:532
    p_out.header.AddWidget2(swap_btn, 0);        // pages.zig:533

    const output_count = QLabel.New5("0 characters", p_out.panel);  // pages.zig:535
    output_count.SetObjectName("countLabel");    // pages.zig:536
    p_out.v.AddWidget2(output_count, 0);         // pages.zig:537

    scroll_layout.AddStretch();                  // pages.zig:539
    parent_layout.AddWidget2(scroll_host, 1);    // pages.zig:540
```

Copy and To Input are injected into the panel's *header* — they appear in the caption
row, pushed right by the `AddStretch` from `newPanel`. The output pane gets its own
object name so QSS tints it differently (`QPlainTextEdit#outputPane`).

**Status + assembly.** Lines 542–568:

```zig
    const status = QLabel.New5("", page);        // pages.zig:542
    status.SetObjectName("status");              // pages.zig:543
    parent_layout.AddWidget2(status, 0);         // pages.zig:544

    const form = Form{
        .category = category,                    // pages.zig:547
        .combo = combo,                          // pages.zig:548
        .keyword_edit = keyword_edit,            // pages.zig:549
        .password_edit = password_edit,          // pages.zig:550
        .kdf_combo = kdf_combo,                  // pages.zig:551
        .num1 = num1,                            // pages.zig:552
        .num2 = num2,                            // pages.zig:553
        .num1_label = num1_label,                // pages.zig:554
        .num2_label = num2_label,                // pages.zig:555
        .input = input,                          // pages.zig:556
        .output = output,                        // pages.zig:557
        .status = status,                        // pages.zig:558
        .input_count = input_count,              // pages.zig:559
        .output_count = output_count,            // pages.zig:560
        .copy_btn = copy_btn,                    // pages.zig:561
        .swap_btn = swap_btn,                    // pages.zig:562
    };
    updateCipherFields(form);                    // pages.zig:564
    category.OnCurrentIndexChanged(onCategoryChanged);  // pages.zig:565
    combo.OnCurrentIndexChanged(onCipherChanged);      // pages.zig:566
    return form;                                 // pages.zig:567
}
```

The status line sits at the bottom of the *page*, below the scroll area. All widget
handles are packed into the `Form`. Three finishing touches: `updateCipherFields`
applies the *initial* state before any interaction, and both combos get their
handlers — category changes re-fill the algorithm list, algorithm changes re-tune
the key fields.

### 5.8 `onCategoryChanged` + `onCipherChanged` — lines 570–582

```zig
fn onCategoryChanged(self: QComboBox, index: i32) callconv(.c) void {  // pages.zig:570
    const f = if (self.ptr == text_form.category.ptr) &text_form else &file_form;  // pages.zig:571
    _ = index;
    repopulateAlgorithmCombo(f);                 // pages.zig:573
    updateCipherFields(f.*);                     // pages.zig:574
    updateActionButtons(f.*);                    // pages.zig:575
}

fn onCipherChanged(self: QComboBox, index: i32) callconv(.c) void {  // pages.zig:578
    const f = if (self.ptr == text_form.combo.ptr) &text_form else &file_form;  // pages.zig:579
    _ = index;
    updateCipherFields(f.*);                     // pages.zig:581
}
```

Both forms share these handlers. To know *which* form fired, they compare `.ptr` of
the `self` combo against the two globals (`[§3.6](ui-walkthrough.md#36-selectnav--selecthome--lines-90-99)`
has the same trick for nav buttons). Default: Text form.

Category change is the heavier path — it needs a new algorithm list, a key-field
reshuffle, *and* a swap between Encrypt/Decrypt and Hash buttons. A plain algorithm
change only re-tunes the key fields.

### 5.9 `repopulateAlgorithmCombo` — lines 584–596

```zig
fn repopulateAlgorithmCombo(f: *Form) void {     // pages.zig:584
    _ = f.combo.BlockSignals(true);              // pages.zig:585
    defer _ = f.combo.BlockSignals(false);       // pages.zig:586

    f.combo.Clear();                             // pages.zig:588
    switch (f.category.CurrentIndex()) {         // pages.zig:589
        0 => for (classical_names) |name| f.combo.AddItem(name),  // pages.zig:590
        1 => for (modern_names) |name| f.combo.AddItem(name),     // pages.zig:591
        2 => for (hash_names) |name| f.combo.AddItem(name),       // pages.zig:592
        else => unreachable,                     // pages.zig:593
    }
    f.combo.SetCurrentIndex(0);                  // pages.zig:595
}
```

Swap the algorithm list based on category. Two subtle points:

- **`BlockSignals(true)`** (with `defer` to restore) — refilling the combo would
  otherwise fire `OnCurrentIndexChanged` and trigger `updateCipherFields` *mid-swap*,
  on stale widget state. Signals are silenced for the duration.
- `SetCurrentIndex(0)` lands on the first algorithm of the new category.

### 5.10 `updateActionButtons` — lines 598–603

```zig
fn updateActionButtons(f: Form) void {           // pages.zig:598
    const is_hash = f.category.CurrentIndex() == 2;  // pages.zig:599
    f.enc_btn.SetVisible(!is_hash);              // pages.zig:600
    f.dec_btn.SetVisible(!is_hash);              // pages.zig:601
    f.hash_btn.SetVisible(is_hash);              // pages.zig:602
}
```

Encrypt/Decrypt **or** Hash, never both. Hash category → only the Hash button shows.
This is what makes the button trio from §5.3/§5.4 reactive.

### 5.11 `updateCipherFields` — lines 605–662

**Category-wide visibility.** Lines 605–619:

```zig
fn updateCipherFields(f: Form) void {            // pages.zig:605
    const cat = f.category.CurrentIndex();       // pages.zig:606
    const is_modern = cat == 1;                  // pages.zig:607
    const is_hash = cat == 2;                    // pages.zig:608

    f.password_edit.SetVisible(is_modern);       // pages.zig:610
    f.kdf_combo.SetVisible(is_modern);           // pages.zig:611

    f.keyword_edit.SetVisible(false);            // pages.zig:613
    f.num1_label.SetVisible(false);              // pages.zig:614
    f.num1.SetVisible(false);                    // pages.zig:615
    f.num2_label.SetVisible(false);              // pages.zig:616
    f.num2.SetVisible(false);                    // pages.zig:617

    if (is_modern or is_hash) return;            // pages.zig:619
```

Modern shows password + KDF and hides the whole classical key row. Hash hides both.
Only Classical falls through to the per-cipher logic below.

**Classical truth table.** Lines 621–630:

```zig
    const idx = f.combo.CurrentIndex();          // pages.zig:621
    const use_keyword = idx == 3 or idx == 4 or idx == 8 or idx == 9 or idx == 10;  // pages.zig:622
    const use_num2 = idx == 2;                   // pages.zig:623
    const use_num1 = idx != 3 and idx != 4 and idx != 8 and idx != 9 and idx != 10;  // pages.zig:624

    f.keyword_edit.SetVisible(use_keyword);      // pages.zig:626
    f.num1_label.SetVisible(use_num1);           // pages.zig:627
    f.num1.SetVisible(use_num1);                 // pages.zig:628
    f.num2_label.SetVisible(use_num2);           // pages.zig:629
    f.num2.SetVisible(use_num2);                 // pages.zig:630
```

Keyword ciphers are 3, 4, 8, 9, 10 (Autokey, Vigenere, Beaufort, Columnar, Bifid).
Only Affine (2) uses the second number. Everything else uses the primary number.

**Labels.** Lines 632–641:

```zig
    const num1_text = switch (idx) {             // pages.zig:632
        0 => "Shift",                            // pages.zig:633  Caesar
        1 => "key",                              // pages.zig:634  Multiplicative
        2 => "key 1",                            // pages.zig:635  Affine
        5 => "Rails",                            // pages.zig:636  Zigzag
        else => "",                              // pages.zig:637  keyword ciphers
    };
    const num2_text = if (use_num2) "key 2" else "";  // pages.zig:639
    if (num1_text.len != 0) f.num1_label.SetText(num1_text);  // pages.zig:640
    if (num2_text.len != 0) f.num2_label.SetText(num2_text);  // pages.zig:641
```

Labels relabel per cipher — "Shift" for Caesar, "Rails" for Zigzag, "key 1"/"key 2"
for Affine.

**Ranges.** Lines 643–661:

```zig
    switch (idx) {                               // pages.zig:643
        0 => { f.num1.SetRange(0, 25); f.num1.SetValue(3); },  // pages.zig:644–647
        1 => { f.num1.SetRange(0, 25); f.num1.SetValue(3); },  // pages.zig:648–651
        2 => { f.num1.SetRange(1, 25); f.num1.SetValue(3); },  // pages.zig:652–655
        5 => { f.num1.SetRange(2, 10); f.num1.SetValue(3); },  // pages.zig:656–659
        else => {},
    }
}
```

Ranges differ per cipher: Affine's `a` must be 1–25 (0 breaks it), Zigzag's rails
2–10, Caesar/Multiplicative 0–25. SetValue resets to a sane default every switch.

### 5.12 `onTitleGlow` — lines 664–669

```zig
fn onTitleGlow(self: QTimer) callconv(.c) void { // pages.zig:664
    _ = self;
    glow_phase += 0.18;                          // pages.zig:666
    const pulse = 0.5 + 0.5 * @sin(glow_phase);  // pages.zig:667
    title_effect.SetBlurRadius(8 + 8 * pulse);   // pages.zig:668
}
```

The timer's callback. `glow_phase` advances a fixed step per tick; `@sin` turns that
into a smooth 0..1 wave; blur swings 8–16px. Result: the glow breathes. This is the
entire animation.

### 5.13 Text handlers — lines 671–692

```zig
fn onTextEncrypt(self: QPushButton) callconv(.c) void {  // pages.zig:671
    _ = self;
    execute(&text_form, .encrypt);               // pages.zig:673
}
fn onTextDecrypt(self: QPushButton) callconv(.c) void {  // pages.zig:676
    _ = self;
    execute(&text_form, .decrypt);               // pages.zig:678
}
fn onTextHash(self: QPushButton) callconv(.c) void {     // pages.zig:681
    _ = self;
    execute(&text_form, .encrypt);               // pages.zig:683
}
fn onTextClear(self: QPushButton) callconv(.c) void {    // pages.zig:686
    _ = self;
    text_form.input.SetPlainText("");            // pages.zig:688
    text_form.output.SetPlainText("");           // pages.zig:689
    updateFormCounts(&text_form);                // pages.zig:690
    setStatus(&text_form, true, "Cleared.");     // pages.zig:691
}
```

Thin wrappers. Encrypt/Decrypt route to `execute` with a `Mode`; Hash reuses
`.encrypt` because hashing has no direction — the category dispatch inside `execute`
decides what actually happens. Clear empties both panes, refreshes counters, writes
a green status.

### 5.14 File handlers — lines 694–755

**`onFileOpen`.** Lines 694–718:

```zig
fn onFileOpen(self: QPushButton) callconv(.c) void {  // pages.zig:694
    _ = self;
    const path = QFileDialog.GetOpenFileName4(   // pages.zig:696
        gpa,                                     // pages.zig:697  allocator
        main_win,                                // pages.zig:698  parent dialog
        "Open Text File",                        // pages.zig:699  title
        "",                                      // pages.zig:700  start dir
        "Text files (*.txt);;All files (*)",     // pages.zig:701  filter
    );
    if (path.len == 0) return;                   // pages.zig:703  user cancelled
    defer gpa.free(path);                        // pages.zig:704

    const content = readFile(path) catch |err| { // pages.zig:706
        setStatus(&file_form, false, "Failed to read file.");  // pages.zig:707
        _ = QMessageBox.Information(main_win, "Open File", @errorName(err));  // pages.zig:708
        return;
    };
    defer gpa.free(content);                     // pages.zig:711

    file_form.input.SetPlainText(content);       // pages.zig:713
    file_form.output.SetPlainText("");           // pages.zig:714
    file_path_label.SetText(path);               // pages.zig:715
    updateFormCounts(&file_form);                // pages.zig:716
    setStatus(&file_form, true, "File loaded."); // pages.zig:717
}
```

`QFileDialog` pops the native open dialog, returning a heap string (empty on
cancel). `gpa.free` via `defer` — Zig-style manual memory management for Qt return
values. Errors get double feedback: red status line **and** a message box.

**Encrypt/decrypt/save.** Lines 720–755:

```zig
fn onFileEncrypt(self: QPushButton) callconv(.c) void {  // pages.zig:720
    _ = self;
    execute(&file_form, .encrypt);               // pages.zig:722
}
fn onFileDecrypt(self: QPushButton) callconv(.c) void {  // pages.zig:725
    _ = self;
    execute(&file_form, .decrypt);               // pages.zig:727
}
fn onFileHash(self: QPushButton) callconv(.c) void {     // pages.zig:730
    _ = self;
    execute(&file_form, .encrypt);               // pages.zig:732
}
```

Same `execute` path as Text, targeting the File form.

```zig
fn onFileSave(self: QPushButton) callconv(.c) void {     // pages.zig:735
    _ = self;
    const out = file_form.output.ToPlainText(gpa);  // pages.zig:737
    defer gpa.free(out);
    if (out.len == 0) {                          // pages.zig:739
        setStatus(&file_form, false, "Nothing to save. Run encrypt or decrypt first.");  // pages.zig:740
        return;
    }

    const path = QFileDialog.GetSaveFileName3(gpa, main_win, "Save Result", "");  // pages.zig:744
    if (path.len == 0) return;                   // pages.zig:745
    defer gpa.free(path);

    writeFile(path, out) catch |err| {           // pages.zig:748
        setStatus(&file_form, false, "Failed to write file.");  // pages.zig:749
        _ = QMessageBox.Information(main_win, "Save File", @errorName(err));  // pages.zig:750
        return;
    };
    file_path_label.SetText(path);               // pages.zig:753
    setStatus(&file_form, true, "Saved.");       // pages.zig:754
}
```

Guards against empty output, opens a save dialog, writes, reports. `ToPlainText`
retrieves widget text (allocated by `gpa`); `GetSaveFileName3` is the save variant.

### 5.15 `execute` — lines 757–787

The shared orchestrator for encrypt/decrypt/hash on **both** pages.

```zig
fn execute(f: *Form, mode: Mode) void {          // pages.zig:757
    const text = f.input.ToPlainText(gpa);       // pages.zig:758
    defer gpa.free(text);
    if (text.len == 0) {                         // pages.zig:760
        setStatus(f, false, "Nothing to process. Enter some text or load a file.");  // pages.zig:761
        return;
    }

    const is_hash = f.category.CurrentIndex() == 2;  // pages.zig:765
    const out = if (is_hash)
        doHash(f, text) catch |err| {            // pages.zig:767
            setStatus(f, false, "Hash failed."); // pages.zig:768
            _ = QMessageBox.Information(main_win, "Crypto Error", @errorName(err));  // pages.zig:769
            return;
        }
    else
        doCipher(f, text, mode) catch |err| {    // pages.zig:773
            const msg = if (err == error.NoPasswordProvided)  // pages.zig:774
                "Enter a password for the selected algorithm."  // pages.zig:775
            else
                "Invalid key or input for the selected algorithm.";  // pages.zig:777
            setStatus(f, false, msg);            // pages.zig:778
            _ = QMessageBox.Information(main_win, "Crypto Error", @errorName(err));  // pages.zig:779
            return;
        };
    defer gpa.free(out);                         // pages.zig:782

    f.output.SetPlainText(out);                  // pages.zig:784
    updateFormCounts(f);                         // pages.zig:785
    setStatus(f, true, if (is_hash) "Hashed." else if (mode == .encrypt) "Encrypted." else "Decrypted.");  // pages.zig:786
}
```

Read input → guard empty → dispatch on category → fill output → refresh counts →
status. Note the error message is **special-cased**: a missing password gets a
human hint, any other failure gets the generic message. Success and failure both
flow through `setStatus`, so the status line is always consistent.

### 5.16 `doHash` — lines 789–810

```zig
fn doHash(f: *Form, text: []const u8) ![]u8 {   // pages.zig:789
    const algo: modern.HashAlgo = switch (f.combo.CurrentIndex()) {  // pages.zig:790
        0 => .sha256,                            // pages.zig:791
        1 => .sha512,                            // pages.zig:792
        2 => .sha3_256,                          // pages.zig:793
        3 => .blake3,                            // pages.zig:794
        4 => .sha1,                              // pages.zig:795
        5 => .md5,                               // pages.zig:796
        6 => .sha224,                            // pages.zig:797
        7 => .sha384,                            // pages.zig:798
        8 => .sha512_256,                        // pages.zig:799
        9 => .sha3_224,                          // pages.zig:800
        10 => .sha3_384,                         // pages.zig:801
        11 => .sha3_512,                         // pages.zig:802
        12 => .shake128,                         // pages.zig:803
        13 => .shake256,                         // pages.zig:804
        14 => .blake2s256,                       // pages.zig:805
        15 => .blake2b512,                       // pages.zig:806
        else => unreachable,                     // pages.zig:807
    };
    return modern.hash(gpa, algo, text);         // pages.zig:809
}
```

Straight index → enum mapping. The combo index must line up with `hash_names` (§5.0).
All 16 hashes funnel into one `modern.hash` call.

### 5.17 `doCipher` — lines 812–914

**Entry + buffer.** Lines 812–818:

```zig
fn doCipher(f: *Form, text: []const u8, mode: Mode) ![]u8 {  // pages.zig:812
    if (f.category.CurrentIndex() == 1) {        // pages.zig:813
        return doModern(f, text, mode);          // pages.zig:814
    }

    const buf = try gpa.alloc(u8, text.len);     // pages.zig:817
    errdefer gpa.free(buf);                      // pages.zig:818
```

Modern category short-circuits to `doModern` (§5.18). Otherwise allocate an output
buffer sized to the input (classical ciphers never change length). `errdefer` frees
it *only* if an error propagates — the successful path returns it.

**The dispatch switch.** Lines 820–911. Every branch has the same shape: build the
cipher from the form's key widgets, then run encrypt or decrypt:

```zig
        0 => {                                   // pages.zig:821  Caesar
            const c = try Cipher(Caesar).init(.{@as(u8, @intCast(f.num1.Value()))});  // pages.zig:822
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),  // pages.zig:824
                .decrypt => try c.decrypt(text, buf),  // pages.zig:825
            }
        },
```

The `@intCast` shrinks `i32` (spinbox value) → `u8`. The keyword branches fetch
text with `f.keyword_edit.Text(gpa)` and free it with `defer`:

```zig
        3 => {                                   // pages.zig:845  Autokey
            const keyword = f.keyword_edit.Text(gpa);  // pages.zig:846
            defer gpa.free(keyword);
            const c = try Cipher(Autokey).init(.{ gpa, keyword });  // pages.zig:848
            ...
        },
```

| Combo index | Cipher | Keys used | Lines |
|---|---|---|---|
| 0 | Caesar | `num1` (shift) | 821–827 |
| 1 | Multiplicative | `num1` (key) | 828–834 |
| 2 | Affine | `num1` (`a`) + `num2` (`b`) | 835–844 |
| 3 | Autokey | `keyword_edit` | 845–853 |
| 4 | Vigenere | `keyword_edit` | 854–862 |
| 5 | Zigzag | `num1` (rails) | 863–869 |
| 6 | Atbash | (none) | 870–876 |
| 7 | Rot13 | (none) | 877–883 |
| 8 | Beaufort | `keyword_edit` | 884–892 |
| 9 | Columnar Transposition | `keyword_edit` | 893–901 |
| 10 | Bifid | `keyword_edit` | 902–910 |

Zigzag, Columnar and Bifid pass `gpa` into `init` because they build temporary
structures during encryption:

```zig
        5 => {                                   // pages.zig:863  Zigzag
            const c = try Cipher(Zigzag).init(.{ gpa, @as(u8, @intCast(f.num1.Value())) });
            ...
        },
        else => unreachable,                     // pages.zig:911
    }
    return buf;                                  // pages.zig:913
}
```

`else => unreachable` is a Zig assertion: the classical combo only has indices
0–10, so anything else is a programming error. On success the filled buffer
returns to `execute`.

### 5.18 `doModern` — lines 916–946

```zig
fn doModern(f: *Form, text: []const u8, mode: Mode) ![]u8 {  // pages.zig:916
    const password = f.password_edit.Text(gpa);  // pages.zig:917
    defer gpa.free(password);
    if (password.len == 0) return error.NoPasswordProvided;  // pages.zig:919

    const kdf = switch (f.kdf_combo.CurrentIndex()) {  // pages.zig:921
        0 => modern.Kdf.argon2id,                // pages.zig:922
        1 => modern.Kdf.pbkdf2_sha256,           // pages.zig:923
        2 => modern.Kdf.scrypt,                  // pages.zig:924
        else => unreachable,
    };
    const aead = switch (f.combo.CurrentIndex()) {  // pages.zig:927
        0 => modern.Aead.xchacha20_poly1305,     // pages.zig:928
        1 => modern.Aead.chacha20_poly1305,      // pages.zig:929
        2 => modern.Aead.aes256_gcm,             // pages.zig:930
        3 => modern.Aead.aes128_gcm,             // pages.zig:931
        4 => modern.Aead.aes256_gcm_siv,         // pages.zig:932
        5 => modern.Aead.aes128_gcm_siv,         // pages.zig:933
        6 => modern.Aead.aegis256,               // pages.zig:934
        7 => modern.Aead.aegis128l,              // pages.zig:935
        8 => modern.Aead.xsalsa20_poly1305,      // pages.zig:936
        9 => modern.Aead.xchacha12_poly1305,     // pages.zig:937
        10 => modern.Aead.chacha12_poly1305,     // pages.zig:938
        else => unreachable,
    };

    return switch (mode) {                       // pages.zig:942
        .encrypt => modern.encrypt(io, gpa, password, text, .{ .kdf = kdf, .aead = aead }),  // pages.zig:943
        .decrypt => modern.decrypt(io, gpa, password, text),  // pages.zig:944
    };
}
```

The modern path:

1. **Password guard** — empty password is a *typed* error, `error.NoPasswordProvided`,
   which `execute` turns into a friendly message.
2. **KDF switch** — three choices, one enum.
3. **AEAD switch** — combo index → `Aead` enum (matches `modern_names` order).
4. **Direction** — encrypt passes both the KDF and the AEAD in an options struct;
   decrypt passes **no AEAD**. The ciphertext is self-describing (the AEAD and
   params are encoded in the blob), so decrypt reads everything it needs from the
   data itself.

### 5.19 Copy / Swap — lines 948–973

```zig
fn onCopy(self: QPushButton) callconv(.c) void { // pages.zig:948
    const f = if (self.ptr == text_form.copy_btn.ptr) &text_form else &file_form;  // pages.zig:949
    const out = f.output.ToPlainText(gpa);       // pages.zig:950
    defer gpa.free(out);
    if (out.len == 0) {                          // pages.zig:952
        setStatus(f, false, "Nothing to copy. Run encrypt or decrypt first.");
        return;
    }
    const clip = QApplication.Clipboard();       // pages.zig:956
    clip.SetText(out);                           // pages.zig:957
    setStatus(f, true, "Output copied to clipboard.");  // pages.zig:958
}
```

Same `.ptr` dispatch as the combo handlers — but here it tests the **copy button** to
tell Text from File. Copy reads the output pane and pushes it to the system
clipboard (`QApplication.Clipboard()` returns the shared clipboard object).

```zig
fn onSwap(self: QPushButton) callconv(.c) void { // pages.zig:961
    const f = if (self.ptr == text_form.swap_btn.ptr) &text_form else &file_form;  // pages.zig:962
    const out = f.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) {                          // pages.zig:965
        setStatus(f, false, "Nothing to move. Run encrypt or decrypt first.");
        return;
    }
    f.input.SetPlainText(out);                   // pages.zig:969
    f.output.SetPlainText("");                   // pages.zig:970
    updateFormCounts(f);                         // pages.zig:971
    setStatus(f, true, "Result moved to input.");// pages.zig:972
}
```

"To Input" moves the result back into the input pane and clears the output — handy
for chained transforms.

### 5.20 Counts, status, file IO — lines 975–1018

```zig
fn countWords(s: []const u8) usize {             // pages.zig:975
    var n: usize = 0;
    var in_word = false;
    for (s) |c| {                                // pages.zig:978
        const ws = c == ' ' or c == '\t' or c == '\n' or c == '\r';  // pages.zig:979
        if (ws) { in_word = false; }             // pages.zig:980
        else if (!in_word) { n += 1; in_word = true; }  // pages.zig:981
    }
    return n;                                    // pages.zig:982
}
```

A tiny state machine: word count = number of whitespace→non-whitespace transitions.

```zig
fn updateFormCounts(f: *Form) void {             // pages.zig:990
    const in_text = f.input.ToPlainText(gpa);    // pages.zig:991
    defer gpa.free(in_text);
    const out_text = f.output.ToPlainText(gpa);  // pages.zig:993
    defer gpa.free(out_text);

    var in_buf: [96]u8 = undefined;              // pages.zig:996  stack buffer for fmt
    const in_s = std.fmt.bufPrint(&in_buf, "{d} characters · {d} words", .{ in_text.len, countWords(in_text) }) catch "…";  // pages.zig:997
    f.input_count.SetText(in_s);                 // pages.zig:998

    var out_buf: [96]u8 = undefined;
    const out_s = std.fmt.bufPrint(&out_buf, "{d} characters", .{out_text.len}) catch "…";  // pages.zig:1001
    f.output_count.SetText(out_s);               // pages.zig:1002
}
```

Reads both panes, formats the "N characters · M words" strings into a *stack
buffer* (falling back to "…" if formatting fails), and writes them into the count
labels. `bufPrint` into a fixed array avoids any allocation.

```zig
fn setStatus(f: *Form, ok: bool, msg: []const u8) void {   // pages.zig:1005
    f.status.SetObjectName(if (ok) "statusOk" else "statusErr");  // pages.zig:1006
    f.status.SetText(msg);                       // pages.zig:1007
}
```

The status switcher: **re-point the object name** (`statusOk` → green, `statusErr` →
red) and set the text. Changing an object name at runtime re-evaluates the QSS rules
— that is how the status line changes color with zero palette code.

```zig
fn readFile(path: []const u8) ![]u8 {            // pages.zig:1010
    const dir = std.Io.Dir.cwd();
    return try dir.readFileAlloc(io, path, gpa, .unlimited);  // pages.zig:1012
}

fn writeFile(path: []const u8, data: []const u8) !void {     // pages.zig:1015
    const dir = std.Io.Dir.cwd();
    try dir.writeFile(io, .{ .sub_path = path, .data = data });  // pages.zig:1017
}
```

Plain Zig file IO. `io` is the `std.Io` saved in `buildUi` (pages.zig:135).
`.unlimited` = no size cap on the file read.

---

## 6. The full picture

Everything so far, end to end:

```
BOOT
main() ──► theme.init  (dark/light QSS, persisted)
     ──► pages.buildUi ──► 4 pages registered in stack (0,1,2,3)
            ├─ sidebar.init + sidebar.build  (nav column)
            └─ sidebar.selectHome            (boot on Home)

IDLE ──► QApplication.Exec()  event loop waits

USER clicks "Encrypt" on Text page (Classical / Caesar)
        ▼
onTextEncrypt (pages.zig:671)
        │  mode = .encrypt
        ▼
execute(&text_form, .encrypt) (pages.zig:757)
        │  reads input pane, category == 0 → doCipher
        ▼
doCipher(text_form, text, .encrypt) (pages.zig:812)
        │  switch(combo index) → Cipher(Caesar).init(.{shift})
        │  → cipher.encrypt(text, buf)        ◄── src/cipher.zig
        ▼
result buffer
        │  output.SetPlainText(result)
        │  updateFormCounts  → "12 characters · 3 words"
        │  setStatus(true, "Encrypted.")      → QSS statusOk = green
        ▼
event loop resumes, waiting for the next click

USER picks category "Modern", algorithm "AES-256-GCM", clicks "Encrypt"
        ▼
execute → category == 1 → doCipher → doModern (pages.zig:916)
        │  password guard → KDF switch → AEAD switch
        ▼
modern.encrypt(io, gpa, password, text, .{ .kdf, .aead })  ◄── src/modern.zig
        ▼
self-describing ciphertext blob → output pane

USER picks category "Hash", algorithm "SHA-256", clicks "Hash"
        ▼
execute → category == 2 → doHash (pages.zig:789)
        │  combo index → HashAlgo enum
        ▼
modern.hash(gpa, .sha256, text)               ◄── src/modern.zig
        ▼
hex digest → output pane
```

### The connections that make it all hold together

| Connection | Mechanism | Where |
|---|---|---|
| Nav button → page | `OnClicked` → `SetCurrentIndex` on the shared stack | sidebar.zig:104, 110, 116, 122 |
| Sidebar ↔ stack | `init` handshake before `build` | pages.zig:138–140, sidebar.zig:29–31 |
| Pages ↔ slot numbers | `PageIndex` enum + registration order | sidebar.zig:13, pages.zig:143–146 |
| Category → algorithm list | `OnCurrentIndexChanged` → `repopulateAlgorithmCombo` (signals blocked) | pages.zig:565, 584–596 |
| Category/algorithm → key widgets | `updateCipherFields` visibility + labels + ranges | pages.zig:605–662 |
| Category → action buttons | `updateActionButtons` Encrypt/Decrypt vs Hash | pages.zig:598–603 |
| Form widgets ↔ handlers | `Form` struct + globals `text_form`/`file_form` | pages.zig:98, 125–126 |
| Which form a signal came from | `.ptr` identity comparison | pages.zig:571, 579, 949, 962 |
| Styling | `SetObjectName` ↔ QSS `#name` rules | everywhere → theme.zig → style.zig → `src/themes/*.qss` |
| Theme switch | `QSettings` round-trip + `SetStyleSheet` swap | theme.zig:62–89 |
| Cipher math (classical) | `execute` → `doCipher` → `cipher.zig` | pages.zig:812 → src/cipher.zig |
| Cipher math (modern) | `execute` → `doCipher` → `doModern` → `modern.zig` | pages.zig:916 → src/modern.zig |
| Hashing | `execute` → `doHash` → `modern.hash` | pages.zig:789 → src/modern.zig |
| Missing password UX | `error.NoPasswordProvided` special-cased | pages.zig:774–776, 919 |

And the rule of thumb for reading any new Qt code in this repo: **find the
constructor, find the `SetObjectName`, find the `OnXxx` connection.** Those three
lines tell you what it is, how it looks, and what it does when the user touches it.
