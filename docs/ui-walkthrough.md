# Oh My Crypto — Step-by-Step UI Walkthrough

A line-by-line walkthrough of `src/main.zig` and `src/pages.zig` in the order the
program actually runs. Companion to [`docs/ui.md`](ui.md), which explains the Qt 6
concepts (widgets, layouts, signals, QSS) from scratch.

> Reading convention: each heading names a file and function. Quoted code keeps the
> real line numbers from the source. A comment like `// main.zig:54` means "this is
> the code that lives at line 54 of `main.zig`". Concepts first introduced in
> `docs/ui.md` are cited like `[§2.2 layouts](ui.md#22-layouts--automatic-arrangement)`.

---

## 1. How `main.zig` and `pages.zig` connect

Two files, one handoff. `main.zig` owns the app, the window, and the sidebar.
`pages.zig` owns the four pages. They share three things:

1. **`stack`** — a `QStackedWidget`. `main.zig` creates it and passes it to
   `pages.zig`, which fills it with pages. `main.zig`'s nav buttons then flip the
   same stack to switch pages.
2. **`PageIndex`** — the same enum declared in both files; the numbers are the page
   slot positions in the stack.
3. **`gpa` + `io`** — the allocator and IO the main thread provides; `pages.zig`
   stashes them as globals so later button handlers can allocate memory.

Boot sequence in one picture:

```
main()
 ├─ qt6.init
 ├─ QApplication.New → qapp
 ├─ SetStyleSheet(style.qss)
 ├─ QMainWindow.New2 → win
 ├─ root = QWidget + QHBoxLayout
 │   ├─ sidebar QWidget  (+ buildSidebar: brand, 4 nav buttons, version)
 │   └─ stack QStackedWidget
 ├─ win.SetCentralWidget(root)
 ├─ pages.buildAll(gpa, io, win, stack)
 │   ├─ buildHome()   → stack slot 0
 │   ├─ buildText()   → stack slot 1
 │   ├─ buildFile()   → stack slot 2
 │   ├─ buildAbout()  → stack slot 3
 │   └─ show Home
 ├─ selectNav(&nav_home)
 ├─ win.Show()
 └─ QApplication.Exec()      ← event loop runs until window closes
```

---

## 2. `src/main.zig` line by line

### 2.1 Imports and aliases — lines 1–16

```zig
const std = @import("std");                    // main.zig:1   Zig standard library
const qt6 = @import("libqt6zig");              // main.zig:2   the Qt bindings
const pages = @import("pages.zig");            // main.zig:3   our page builders
const style = @import("style.zig");            // main.zig:4   the stylesheet module
```

`qt6` is the whole Qt binding namespace. The next block copies the classes this file
uses into short local names (`[§3.1](ui.md#31-the-qt6-import)`):

```zig
const QApplication = qt6.QApplication;         // main.zig:6
const QWidget = qt6.QWidget;                   // main.zig:7
const QMainWindow = qt6.QMainWindow;           // main.zig:8
const QStackedWidget = qt6.QStackedWidget;     // main.zig:9
const QPushButton = qt6.QPushButton;           // main.zig:10
const QLabel = qt6.QLabel;                     // main.zig:11
const QBoxLayout = qt6.QBoxLayout;             // main.zig:12
const QHBoxLayout = qt6.QHBoxLayout;           // main.zig:13
```

Lines 15–16 are the magic numbers that Qt's enum uses for layout directions. The
bindings expose them as plain `i32`:

```zig
const left_to_right: i32 = 0;                  // main.zig:15  Qt::Horizontal
const top_to_bottom: i32 = 2;                  // main.zig:16  Qt::Vertical
```

`QHBoxLayout.New` hardcodes horizontal; `QBoxLayout.New2(direction, ...)` takes the
number, so the code passes `top_to_bottom` for vertical stacks.

### 2.2 `PageIndex` and globals — lines 18–30

```zig
const PageIndex = enum(i32) {
    home = 0, text = 1, file = 2, about = 3,
};                                             // main.zig:18–23
```

The four pages get stable numbers. These **must** match the order `pages.buildAll`
appends pages to the stack, or nav will show the wrong page.

```zig
var stack: QStackedWidget = undefined;         // main.zig:25
var nav_home: QPushButton = undefined;         // main.zig:27
var nav_text: QPushButton = undefined;         // main.zig:28
var nav_file: QPushButton = undefined;         // main.zig:29
var nav_about: QPushButton = undefined;        // main.zig:30
```

Module-scope `var`s (`[§4.3](ui.md#43-why-globals)`). They start as `undefined`
because they are filled in later (`stack` at line 62, nav buttons in `buildSidebar`).
`pages.buildAll` also stashes `gpa`/`io`/`stack` in globals for the same reason: the
signal callbacks are plain functions with no state pointer.

### 2.3 `main()` — lines 32–75

```zig
pub fn main(init: std.process.Init) !void {    // main.zig:32
    const argv = try qt6.init(init.gpa, init.minimal.args);   // main.zig:33
    defer qt6.deinit(init.gpa, argv);          // main.zig:34
    var argc: i32 = @intCast(argv.len);        // main.zig:35
```

`qt6.init` prepares the binding (and the backing C++ side) and normalizes the
command-line args into Qt format. `defer` guarantees cleanup when `main` returns.
`argc`/`argv` get handed to `QApplication`, which expects them.

```zig
    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);  // main.zig:37
    defer qapp.Delete();                       // main.zig:38
```

There is exactly **one** `QApplication` per Qt program. It owns the event loop and
the app-wide state (clipboard, stylesheet, font defaults). `init.arena.allocator()`
is borrowed for the app's long-lived allocations.

```zig
    qapp.SetStyleSheet(style.qss);             // main.zig:40
```

Apply the theme. `style.qss` is the embedded text of `ayu_dark.qss`
([§6](ui.md#6-theming--srcayu_darkqss)). A stylesheet set on the application
applies to every widget in it.

```zig
    const win = QMainWindow.New2();            // main.zig:42
    defer win.Delete();                        // main.zig:43
    win.SetWindowTitle("Oh My Crypto");        // main.zig:44
    win.SetMinimumSize2(820, 600);             // main.zig:45
    win.Resize(1040, 700);                     // main.zig:46
```

The OS window: title, a floor size (so the layout never collapses), and the initial
size.

```zig
    const root = QWidget.New2();               // main.zig:48
    const root_box = QHBoxLayout.New(root);    // main.zig:49
    root_box.SetContentsMargins(0, 0, 0, 0);   // main.zig:50
    root_box.SetSpacing(0);                    // main.zig:51
```

A `QMainWindow` needs a single **central widget**. `root` is a plain container whose
horizontal layout splits the window in two. Zero margins/spacing = the two columns
touch edge-to-edge (the sidebar draws its own background).

```zig
    const sidebar = QWidget.New2();            // main.zig:53
    sidebar.SetObjectName("sidebar");          // main.zig:54
    sidebar.SetFixedWidth(200);                // main.zig:55
    const sv = QBoxLayout.New2(top_to_bottom, sidebar);  // main.zig:56
    sv.SetContentsMargins(16, 28, 16, 20);     // main.zig:57
    sv.SetSpacing(4);                          // main.zig:58
    buildSidebar(sidebar, sv);                 // main.zig:59
    root_box.AddWidget2(sidebar, 0);           // main.zig:60
```

The left column. `SetObjectName("sidebar")` is the QSS hook: `QWidget#sidebar` gets
the darker background [§6](ui.md#6-theming--srcayu_darkqss). `SetFixedWidth(200)`
locks its width. The `QBoxLayout` is vertical; `buildSidebar` (section 2.7) pours
content into it. Stretch `0` = sidebar keeps its fixed size.

```zig
    stack = QStackedWidget.New2();             // main.zig:62
    root_box.AddWidget2(stack, 1);             // main.zig:63
```

The content area: a stack holding all four pages, showing one at a time. Stretch `1`
= it absorbs all extra space when the window grows [§2.2](ui.md#22-layouts--automatic-arrangement).

```zig
    win.SetCentralWidget(root);                // main.zig:65
```

Hang the whole split on the window.

```zig
    pages.buildAll(init.gpa, init.io, win, stack);   // main.zig:67
```

**The handoff.** `pages.zig` builds the four pages into `stack` (section 3.2). It
also saves `gpa`/`io`/`win` for its handlers. After this call the stack is full.

```zig
    selectNav(&nav_home);                      // main.zig:68
    win.Show();                                // main.zig:70
    _ = QApplication.Exec();                   // main.zig:72
```

`selectNav` lights up the Home button before anything is drawn. `Show` makes the
window visible. `Exec` starts the event loop `[§2.4](ui.md#24-the-event-loop)` and
only returns when the window closes.

```zig
    try std.Io.File.stdout().writeStreamingAll(init.io, "OK!\n");  // main.zig:74
}
```

After the loop ends, print `OK!` so running the binary from a terminal confirms a
clean exit.

### 2.4 `newNav` — lines 77–83

```zig
fn newNav(parent: QWidget, text: []const u8) QPushButton {   // main.zig:77
    const b = QPushButton.New5(text, parent);  // main.zig:78
    b.SetObjectName("navBtn");                 // main.zig:79
    b.SetCheckable(true);                      // main.zig:80
    b.SetFixedHeight(40);                      // main.zig:81
    return b;
}
```

A factory for the four nav buttons. `QPushButton.New5(text, parent)` builds a button
with a caption and a parent widget (`[§3.2](ui.md#32-constructors-new-new2--new5)`).
`SetCheckable(true)` gives the button an on/off "checked" state — which the QSS
`:checked` rule paints gold. `SetFixedHeight(40)` gives all four buttons the same
height.

### 2.5 `selectNav` — lines 85–90

```zig
fn selectNav(active: *const QPushButton) void {   // main.zig:85
    nav_home.SetChecked(nav_home.ptr == active.ptr);  // main.zig:86
    nav_text.SetChecked(nav_text.ptr == active.ptr);  // main.zig:87
    nav_file.SetChecked(nav_file.ptr == active.ptr);  // main.zig:88
    nav_about.SetChecked(nav_about.ptr == active.ptr); // main.zig:89
}
```

"Exactly one button checked." For each nav button it checks the identity test
`its.ptr == active.ptr` and sets checked state from the boolean result. `.ptr` is
the underlying C pointer — the reliable way to compare two widget handles
(`[§8](ui.md#8-glossary)`). So the button that matches `active` gets `true`, the
other three get `false`.

### 2.6 The nav handlers — lines 92–114

```zig
fn onNavHome(self: QPushButton) callconv(.c) void {   // main.zig:92
    _ = self;                                // main.zig:93  ignore the widget arg
    selectNav(&nav_home);                    // main.zig:94  highlight Home
    stack.SetCurrentIndex(@intFromEnum(PageIndex.home));  // main.zig:95  show page 0
}
```

`onNavText` (98), `onNavFile` (104), `onNavAbout` (110) are identical except they
use `&nav_text`, `&nav_file`, `&nav_about` and the matching `PageIndex` value.

The two-line recipe: **flip the highlight, flip the page.** `SetCurrentIndex`
tells the stack which page to display. `@intFromEnum` converts the enum value to the
`i32` the stack expects.

### 2.7 `buildSidebar` — lines 116–148

```zig
fn buildSidebar(parent: QWidget, v: QBoxLayout) void {   // main.zig:116
    const brand = QLabel.New5("Oh My Crypto", parent);   // main.zig:117
    brand.SetObjectName("brand");            // main.zig:118
    v.AddWidget2(brand, 0);                  // main.zig:119

    const tagline = QLabel.New5("classical ciphers", parent);  // main.zig:121
    tagline.SetObjectName("brandTag");       // main.zig:122
    v.AddWidget2(tagline, 0);                // main.zig:123

    v.AddSpacing(28);                        // main.zig:125  gap before buttons
```

Labels first: the big brand name and the muted tagline. Both get object names so QSS
can size/style them (`QLabel#brand`, `QLabel#brandTag`). `AddSpacing` inserts a fixed
28-pixel gap.

```zig
    nav_home = newNav(parent, "Home");       // main.zig:127
    nav_home.OnClicked(onNavHome);           // main.zig:128
    v.AddWidget2(nav_home, 0);               // main.zig:129
```

The four buttons in order. The assignment to the global (`nav_home`) happens *here*,
inside the builder, which is why `selectNav` can reference it later. `OnClicked`
wires the signal `[§2.3](ui.md#23-signals-and-slots--zig-callbacks)`. Same pattern
repeats for Text (131–133), File (135–137), About (139–141).

```zig
    v.AddStretch();                          // main.zig:143  push version to bottom

    const version = QLabel.New5("v0.1.0", parent);   // main.zig:145
    version.SetObjectName("version");        // main.zig:146
    v.AddWidget2(version, 0);                // main.zig:147
}
```

`AddStretch` inserts a flexible empty space that eats all leftover vertical room —
the version label is pinned to the bottom edge.

`main.zig` is done. The sidebar exists, the stack exists, the pages are built. Now
the pages themselves.

---

## 3. `src/pages.zig` line by line

### 3.1 Imports, structs, globals — lines 1–75

```zig
const std = @import("std");                  // pages.zig:1
const qt6 = @import("libqt6zig");            // pages.zig:2
const ciphers = @import("oh_my_crypto").cipher;   // pages.zig:3  the cipher module
```

Lines 5–23 alias every Qt class this file touches — a longer list than main.zig
(`QSpinBox`, `QComboBox`, `QPlainTextEdit`, `QGridLayout`, `QFileDialog`,
`QMessageBox`, `QTimer`, `QColor`, `QGraphicsDropShadowEffect`, `QClipboard`, ...).

```zig
const Cipher = ciphers.Cipher;               // pages.zig:25
const Caesar = ciphers.Caesar;               // pages.zig:26
...                                          // pages.zig:27–31 (6 cipher types)
```

The cipher types are pulled up so `doCipher` can build instances.

```zig
const align_center: i32 = 132;               // pages.zig:33  Qt::AlignCenter
const top_to_bottom: i32 = 2;                // pages.zig:34
```

The layout direction (same `2` as main.zig) plus the alignment flag for centered
labels. `132` is the `Qt::AlignCenter` value.

```zig
const PageIndex = enum(i32) { home = 0, text = 1, file = 2, about = 3 };  // pages.zig:36–41
```

The same enum as main.zig — the slot numbers must agree. (Duplicated by design; the
two files share no common header.)

```zig
const Mode = enum { encrypt, decrypt };      // pages.zig:43–46
```

A tiny enum passed to `execute`/`doCipher` to pick which direction to run.

**The `Form` struct — lines 48–62.** This is the contract between the UI and the
handlers. Every widget the code needs to touch *after* the form is built is stored
here:

```zig
const Form = struct {
    combo: QComboBox,                        // cipher picker
    keyword_edit: QLineEdit,                 // keyword (Autokey / Vigenere)
    num1: QSpinBox,                          // shift / key / rails
    num2: QSpinBox,                          // second key (Affine only)
    num1_label: QLabel,                      // caption above num1
    num2_label: QLabel,                      // caption above num2
    input: QPlainTextEdit,                   // text in
    output: QPlainTextEdit,                  // result out
    status: QLabel,                          // status line
    input_count: QLabel,                     // "N characters · M words"
    output_count: QLabel,                    // "N characters"
    copy_btn: QPushButton,                   // "Copy"
    swap_btn: QPushButton,                   // "To Input"
};
```

**Globals — lines 64–75.** `pages.zig` uses the same trick as main.zig: handlers are
plain `callconv(.c)` functions, so shared state lives in module scope:

```zig
var io: std.Io = undefined;                  // pages.zig:64  stdin/stdout/fs access
var gpa: std.mem.Allocator = undefined;      // pages.zig:65  memory allocator
var main_win: QMainWindow = undefined;       // pages.zig:66  for modal dialogs
var stack: QStackedWidget = undefined;       // pages.zig:67  the page switcher

var text_form: Form = undefined;             // pages.zig:69  the Text page form
var file_form: Form = undefined;             // pages.zig:70  the File page form
var file_path_label: QLabel = undefined;     // pages.zig:71  shows chosen file

var title_effect: QGraphicsDropShadowEffect = undefined;  // pages.zig:73
var title_timer: QTimer = undefined;         // pages.zig:74
var glow_phase: f64 = 0;                     // pages.zig:75  animation counter
```

### 3.2 `buildAll` — lines 77–87

```zig
pub fn buildAll(g: std.mem.Allocator, app_io: std.Io, win: QMainWindow, s: QStackedWidget) void {
    gpa = g;                                 // pages.zig:78  stash allocator
    io = app_io;                             // pages.zig:79  stash IO
    main_win = win;                          // pages.zig:80  stash window
    stack = s;                               // pages.zig:81  stash stack
    buildHome();                             // pages.zig:82
    buildText();                             // pages.zig:83
    buildFile();                             // pages.zig:84
    buildAbout();                            // pages.zig:85
    stack.SetCurrentIndex(@intFromEnum(PageIndex.home));  // pages.zig:86
}
```

The one public entry point, called from main.zig:67. It (a) copies the four inputs
into globals so every later callback has access, then (b) builds the four pages in
**the exact order they must occupy stack slots 0–3**. `SetCurrentIndex(home)` lands
on page 0 at startup.

### 3.3 `buildHome` — lines 89–171

```zig
fn buildHome() void {
    const page = QWidget.New2();             // pages.zig:90
    page.SetObjectName("pageHome");          // pages.zig:91
    const v = QBoxLayout.New2(top_to_bottom, page);  // pages.zig:92
    v.SetContentsMargins(48, 64, 48, 48);    // pages.zig:93
    v.SetSpacing(16);                        // pages.zig:94
```

Every page follows the same skeleton: blank `QWidget` → object name (QSS hook) →
vertical layout → margins/spacing. The Home page gets generous margins (64px top)
because it is mostly centered content.

```zig
    v.AddStretch();                          // pages.zig:96  push content to vertical center
```

A stretch at the *top* pushes everything below it toward the middle.

```zig
    const title = QLabel.New5("Oh My Crypto", page);  // pages.zig:98
    title.SetObjectName("title");            // pages.zig:99
    title.SetAlignment(align_center);        // pages.zig:100
    v.AddWidget2(title, 0);                  // pages.zig:101
```

The hero title. `SetAlignment(align_center)` centers the text; QSS `QLabel#title`
makes it 44px bold.

**The glow — lines 103–112.** Two objects work together:

```zig
    title_effect = QGraphicsDropShadowEffect.New2(page);  // pages.zig:103
    title_effect.SetColor(QColor.New5(0xe6, 0xb4, 0x50)); // pages.zig:104  gold
    title_effect.SetOffset3(0);              // pages.zig:105  no positional offset
    title_effect.SetBlurRadius(50);          // pages.zig:106  wide soft glow
    title.SetGraphicsEffect(title_effect);   // pages.zig:107  attach to title
```

A graphics effect = a visual filter drawn on top of the widget. A drop shadow with a
gold color and blur is a glow.

```zig
    title_timer = QTimer.New2(page);         // pages.zig:109
    title_timer.SetInterval(80);             // pages.zig:110  tick every 80 ms
    title_timer.OnTimeout(onTitleGlow);      // pages.zig:111  pulse callback
    title_timer.Start(80);                   // pages.zig:112  begin
```

A `QTimer` fires `timeout` repeatedly; `onTitleGlow` (section 3.8) tweaks the blur
each tick → breathing glow. Timer is parented to `page`, so Qt cleans it up with the
page.

```zig
    const subtitle = QLabel.New5("Encrypt and decrypt text with six classical ciphers", page);
    subtitle.SetObjectName("subtitle");      // pages.zig:118
    subtitle.SetAlignment(align_center);
    v.AddWidget2(subtitle, 0);               // pages.zig:120

    const divider = QLabel.New5("", page);   // pages.zig:122
    divider.SetObjectName("divider");        // pages.zig:123
    divider.SetFixedWidth(96);               // pages.zig:124
    divider.SetFixedHeight(2);               // pages.zig:125
    v.AddWidget3(divider, 0, align_center);  // pages.zig:126
```

A cute trick: the divider is an **empty `QLabel`** whose only role is to carry the
`divider` object name. QSS paints it as a 2px gold bar (`QLabel#divider`). `SetFixed*`
gives it size; `AddWidget3(widget, stretch, alignment)` centers it.

```zig
    v.AddSpacing(36);                        // pages.zig:128
```

**The chips grid — lines 130–151.** A separate host widget with a grid layout:

```zig
    const chips_host = QWidget.New2();       // pages.zig:130
    chips_host.SetObjectName("chipsHost");   // pages.zig:131
    const chips = QGridLayout.New(chips_host);   // pages.zig:132
    chips.SetHorizontalSpacing(12);          // pages.zig:133
    chips.SetVerticalSpacing(12);            // pages.zig:134
    const ciphers_list = [_][]const u8{
        "Caesar", "Multiplicative", "Affine",
        "Autokey", "Vigenere", "Zigzag",
    };                                       // pages.zig:135–142
    for (ciphers_list, 0..) |name, i| {
        const row: i32 = @intCast(i / 3);    // pages.zig:144  0,0,0,1,1,1
        const col: i32 = @intCast(i % 3);    // pages.zig:145  0,1,2,0,1,2
        const chip = QLabel.New5(name, chips_host);  // pages.zig:146
        chip.SetObjectName("chip");          // pages.zig:147  pill-style badge
        chip.SetAlignment(align_center);     // pages.zig:148
        chips.AddWidget2(chip, row, col);    // pages.zig:149
    }
    v.AddWidget3(chips_host, 0, align_center);  // pages.zig:151
```

A `for` loop turns the six names into a 3×2 grid of pill labels. Row/column are
derived arithmetically from the index. The `chip` object name triggers the rounded
QSS badge look.

```zig
    v.AddSpacing(12);                        // pages.zig:153

    const note = QLabel.New5("Classical ciphers for learning cryptography\n(not for real data).", page);
    note.SetObjectName("note");              // pages.zig:158
    note.SetAlignment(align_center);         // pages.zig:159
    v.AddWidget2(note, 0);                   // pages.zig:160

    v.AddStretch();                          // pages.zig:163  balance top stretch

    const footer = QLabel.New5("Educational tool", page);
    footer.SetObjectName("footer");          // pages.zig:166
    footer.SetAlignment(align_center);       // pages.zig:167
    v.AddWidget2(footer, 0);                 // pages.zig:168

    _ = stack.AddWidget(page);               // pages.zig:170  register as page 0
}
```

The bottom stretch (163) balances the top one (96), centering the block. The final
`stack.AddWidget(page)` is the moment this page becomes **slot 0**.

### 3.4 `buildText` — lines 173–205

```zig
fn buildText() void {
    const page = QWidget.New2();             // pages.zig:174
    page.SetObjectName("pageText");          // pages.zig:175
    const v = QBoxLayout.New2(top_to_bottom, page);  // pages.zig:176
    v.SetContentsMargins(28, 24, 28, 24);    // pages.zig:177
    v.SetSpacing(12);                        // pages.zig:178

    const heading = QLabel.New5("Encrypt / Decrypt Text", page);
    heading.SetObjectName("heading");        // pages.zig:181
    v.AddWidget2(heading, 0);                // pages.zig:182

    const form = buildCipherForm(page, v, true);  // pages.zig:184
    text_form = form;                        // pages.zig:185
```

The `true` argument = the input area is editable (user types text). `buildCipherForm`
builds the whole shared form and returns a `Form`; it is saved to the global
`text_form` so the handlers can reach it.

```zig
    const btns = QHBoxLayout.New(page);      // pages.zig:187
    const btn_enc = QPushButton.New5("Encrypt", page);
    btn_enc.SetObjectName("primaryBtn");     // pages.zig:189
    btn_enc.OnClicked(onTextEncrypt);        // pages.zig:190
    btns.AddWidget2(btn_enc, 1);             // pages.zig:191

    const btn_dec = QPushButton.New5("Decrypt", page);
    btn_dec.SetObjectName("secondaryBtn");   // pages.zig:194
    btn_dec.OnClicked(onTextDecrypt);        // pages.zig:195
    btns.AddWidget2(btn_dec, 1);             // pages.zig:196

    const btn_clear = QPushButton.New5("Clear", page);
    btn_clear.SetObjectName("ghostBtn");     // pages.zig:199
    btn_clear.OnClicked(onTextClear);        // pages.zig:200
    btns.AddWidget2(btn_clear, 0);           // pages.zig:201
    v.AddLayout2(btns, 0);                   // pages.zig:202

    _ = stack.AddWidget(page);               // pages.zig:204  slot 1
}
```

Three buttons in a horizontal row. Stretch factors: Encrypt and Decrypt both `1`
(they split the extra width), Clear `0` (natural size, right side). Each button gets
its own object name → different QSS look. `AddLayout2` nests the button row into the
page's vertical layout. The page lands in **slot 1**.

### 3.5 `buildFile` — lines 207–254

Same skeleton as Text, with file-specific extras.

```zig
    const heading = QLabel.New5("Process Text File", page);
    heading.SetObjectName("heading");        // pages.zig:215
    v.AddWidget2(heading, 0);                // pages.zig:216

    const open_row = QHBoxLayout.New(page);  // pages.zig:218
    const btn_open = QPushButton.New5("Open Text File...", page);
    btn_open.SetObjectName("primaryBtn");    // pages.zig:220
    btn_open.OnClicked(onFileOpen);          // pages.zig:221
    open_row.AddWidget2(btn_open, 0);        // pages.zig:222

    file_path_label = QLabel.New5("No file selected", page);
    file_path_label.SetObjectName("status"); // pages.zig:225
    file_path_label.SetWordWrap(true);       // pages.zig:226
    open_row.AddWidget2(file_path_label, 1); // pages.zig:227
    v.AddLayout2(open_row, 0);               // pages.zig:228
```

An open button plus a path label in one row. The label stretches (`1`) so long paths
have room; `SetWordWrap` lets them break lines.

```zig
    const form = buildCipherForm(page, v, false);  // pages.zig:230
    file_form = form;                        // pages.zig:231
```

Second call to the shared builder, with `false` → input is **read-only** (you don't
type a file, you load one). The result is stored in the global `file_form`.

```zig
    const btns = QHBoxLayout.New(page);      // pages.zig:233
    const btn_enc = QPushButton.New5("Encrypt", page);
    btn_enc.SetObjectName("primaryBtn");     // pages.zig:235
    btn_enc.OnClicked(onFileEncrypt);        // pages.zig:236
    btns.AddWidget2(btn_enc, 1);             // pages.zig:237
    const btn_dec = QPushButton.New5("Decrypt", page);
    btn_dec.SetObjectName("secondaryBtn");   // pages.zig:240
    btn_dec.OnClicked(onFileDecrypt);        // pages.zig:241
    btns.AddWidget2(btn_dec, 1);             // pages.zig:242
    v.AddLayout2(btns, 0);                   // pages.zig:243

    const save_row = QHBoxLayout.New(page);  // pages.zig:245
    const btn_save = QPushButton.New5("Save Result...", page);
    btn_save.SetObjectName("primaryBtn");    // pages.zig:247
    btn_save.OnClicked(onFileSave);          // pages.zig:248
    save_row.AddWidget2(btn_save, 0);        // pages.zig:249
    save_row.AddStretch();                   // pages.zig:250
    v.AddLayout2(save_row, 0);               // pages.zig:251

    _ = stack.AddWidget(page);               // pages.zig:253  slot 2
}
```

Encrypt/Decrypt (same as Text) plus a Save row, where `AddStretch` pins the button
to the left. File page = **slot 2**.

### 3.6 `buildAbout` — lines 256–317

```zig
fn buildAbout() void {
    const page = QWidget.New2();             // pages.zig:257
    page.SetObjectName("pageAbout");         // pages.zig:258
    const v = QBoxLayout.New2(top_to_bottom, page);  // pages.zig:259
    v.SetContentsMargins(28, 24, 28, 24);    // pages.zig:260
    v.SetSpacing(12);                        // pages.zig:261

    const heading = QLabel.New5("About", page);
    heading.SetObjectName("heading");        // pages.zig:264
    v.AddWidget2(heading, 0);                // pages.zig:265

    v.AddSpacing(4);                         // pages.zig:267
```

Then four panels, each via the `newPanel` helper (section 3.7). First panel — intro
with a version badge squeezed into the header row:

```zig
    const p_intro = newPanel(page, v, "Oh My Crypto", 0);   // pages.zig:269
    const badge = QLabel.New5("v0.1.0", p_intro.panel);     // pages.zig:270
    badge.SetObjectName("versionBadge");                    // pages.zig:271
    p_intro.header.AddWidget2(badge, 0);                    // pages.zig:272

    const intro = QLabel.New5(
        "A desktop GUI utility for classical ciphers, written in Zig 0.16.0 with Qt 6.",
        p_intro.panel,                       // pages.zig:277
    );
    intro.SetObjectName("about");            // pages.zig:278
    intro.SetWordWrap(true);                 // pages.zig:279
    p_intro.v.AddWidget2(intro, 0);          // pages.zig:280
```

`newPanel` returns a `Panel` exposing `.panel`, `.v`, `.header`. The badge goes into
the *header* (top-right, after the stretch), the intro text into the panel's body.

```zig
    const p_feat = newPanel(page, v, "Features", 0);  // pages.zig:282
    const bullets = [_][]const u8{ ... };    // pages.zig:283–288
    for (bullets) |b| {
        const line = QLabel.New5(b, p_feat.panel);   // pages.zig:290
        line.SetObjectName("aboutLine");     // pages.zig:291
        line.SetWordWrap(true);
        p_feat.v.AddWidget2(line, 0);        // pages.zig:293
    }
```

The features list is a loop of plain labels — no rich text, no bullets widget; each
string literally starts with `"• "`.

```zig
    const p_warn = newPanel(page, v, "Educational tool", 0);  // pages.zig:296
    ...                                        // warning text label (297–303)

    const p_lic = newPanel(page, v, "License", 0);     // pages.zig:305
    ...                                        // license label (306–312)

    v.AddStretch();                            // pages.zig:314
    _ = stack.AddWidget(page);                 // pages.zig:316  slot 3
}
```

The trailing stretch pushes the panels up. About page = **slot 3**.

### 3.7 `Panel` struct + `newPanel` — lines 319–341

```zig
const Panel = struct {                        // pages.zig:319
    panel: QWidget,                           // the card widget itself
    v: QBoxLayout,                            // the card's body layout
    header: QHBoxLayout,                      // the caption row (extendable)
};
```

The return type of `newPanel` — gives callers handles to keep filling the card after
creation.

```zig
fn newPanel(page: QWidget, parent_layout: QBoxLayout, title_text: []const u8, stretch: i32) Panel {
    const panel = QWidget.New(page);          // pages.zig:326
    panel.SetObjectName("panel");             // pages.zig:327  rounded dark card
    const pv = QBoxLayout.New2(top_to_bottom, panel);  // pages.zig:328
    pv.SetContentsMargins(14, 12, 14, 10);    // pages.zig:329
    pv.SetSpacing(8);                         // pages.zig:330

    const header = QHBoxLayout.New(panel);    // pages.zig:332
    const title = QLabel.New5(title_text, panel);   // pages.zig:333
    title.SetObjectName("panelTitle");        // pages.zig:334  small gold caption
    header.AddWidget2(title, 0);              // pages.zig:335
    header.AddStretch();                      // pages.zig:336  caption pinned left

    pv.AddLayout2(header, 0);                 // pages.zig:338
    parent_layout.AddWidget2(panel, stretch); // pages.zig:339  slot into the page
    return .{ .panel = panel, .v = pv, .header = header };  // pages.zig:340
}
```

The card pattern: a `QWidget` with the `panel` object name (QSS gives it background,
border, rounded corners), a caption header row with a stretch (so future buttons can
go right), and the body layout. Note `QWidget.New(page)` vs `QWidget.New2()` — `New`
takes a parent, `New2` has none. Both are valid; parenting matters for cleanup.

### 3.8 `buildCipherForm` — lines 343–439

The heart of the Text and File pages. Signature:

```zig
fn buildCipherForm(page: QWidget, parent_layout: QBoxLayout, editable_input: bool) Form {
```

Three arguments: the page, its layout (the form appends its panels there), and
whether the input should be editable. It returns a fully-populated `Form`.

**Cipher panel.** Lines 344–384:

```zig
    const p_cipher = newPanel(page, parent_layout, "Cipher & Key", 0);  // pages.zig:344

    const combo = QComboBox.New(p_cipher.panel);  // pages.zig:346
    combo.AddItem("Caesar");                 // pages.zig:347
    combo.AddItem("Multiplicative");         // pages.zig:348
    combo.AddItem("Affine");                 // pages.zig:349
    combo.AddItem("Autokey");                // pages.zig:350
    combo.AddItem("Vigenere");               // pages.zig:351
    combo.AddItem("Zigzag");                 // pages.zig:352
    p_cipher.v.AddWidget2(combo, 0);         // pages.zig:353
```

The drop-down. Its `currentIndex` (0–5) is the master switch for everything later:
which key fields show, what labels say, which cipher runs.

```zig
    const key_row = QHBoxLayout.New(p_cipher.panel);   // pages.zig:355

    const keyword_edit = QLineEdit.New(p_cipher.panel);   // pages.zig:357
    keyword_edit.SetPlaceholderText("Keyword (letters only)");  // pages.zig:358
    keyword_edit.SetVisible(false);          // pages.zig:359  hidden until needed
    key_row.AddWidget2(keyword_edit, 3);     // pages.zig:360

    const num1_label = QLabel.New5("Shift", p_cipher.panel);  // pages.zig:362
    num1_label.SetObjectName("keyLabel");    // pages.zig:363
    key_row.AddWidget2(num1_label, 0);       // pages.zig:364

    const num1 = QSpinBox.New(p_cipher.panel);   // pages.zig:366
    num1.SetRange(0, 25);                    // pages.zig:367
    num1.SetValue(3);                        // pages.zig:368
    num1.SetFixedHeight(32);                 // pages.zig:369
    key_row.AddWidget2(num1, 1);             // pages.zig:370

    const num2_label = QLabel.New5("b", p_cipher.panel);  // pages.zig:372
    num2_label.SetObjectName("keyLabel");    // pages.zig:373
    num2_label.SetVisible(false);            // pages.zig:374
    key_row.AddWidget2(num2_label, 0);       // pages.zig:375

    const num2 = QSpinBox.New(p_cipher.panel);   // pages.zig:377
    num2.SetRange(0, 25);                    // pages.zig:378
    num2.SetValue(9);                        // pages.zig:379
    num2.SetVisible(false);                  // pages.zig:380
    num2.SetFixedHeight(32);                 // pages.zig:381
    key_row.AddWidget2(num2, 1);             // pages.zig:382

    p_cipher.v.AddLayout2(key_row, 0);       // pages.zig:384
```

The key row holds **all** possible key inputs: a keyword field, a primary number,
and a secondary number. The ones not relevant to the current cipher start hidden
(`SetVisible(false)`) and `updateCipherFields` toggles them. Stretch weights give
the keyword field `3` (wide) and each spinbox `1`.

**Input panel.** Lines 386–394:

```zig
    const p_in = newPanel(page, parent_layout, "Input", 1);   // pages.zig:386
    const input = QPlainTextEdit.New(p_in.panel);   // pages.zig:387
    input.SetPlaceholderText("Type or paste text here...");  // pages.zig:388
    input.SetReadOnly(!editable_input);      // pages.zig:389
    p_in.v.AddWidget2(input, 1);             // pages.zig:390

    const input_count = QLabel.New5("0 characters", p_in.panel);  // pages.zig:392
    input_count.SetObjectName("countLabel"); // pages.zig:393
    p_in.v.AddWidget2(input_count, 0);       // pages.zig:394
```

Note `editable_input` drives `SetReadOnly` — the same builder produces an editable
Text page and a read-only File page. The count label sits under the text area.

**Output panel.** Lines 396–415:

```zig
    const p_out = newPanel(page, parent_layout, "Output", 1);  // pages.zig:396
    const output = QPlainTextEdit.New(p_out.panel);  // pages.zig:397
    output.SetObjectName("outputPane");      // pages.zig:398
    output.SetReadOnly(true);                // pages.zig:399
    output.SetPlaceholderText("Result appears here...");  // pages.zig:400
    p_out.v.AddWidget2(output, 1);           // pages.zig:401

    const copy_btn = QPushButton.New5("Copy", p_out.panel);  // pages.zig:403
    copy_btn.SetObjectName("miniBtn");       // pages.zig:404
    copy_btn.OnClicked(onCopy);              // pages.zig:405
    p_out.header.AddWidget2(copy_btn, 0);    // pages.zig:406

    const swap_btn = QPushButton.New5("To Input", p_out.panel);  // pages.zig:408
    swap_btn.SetObjectName("miniBtn");       // pages.zig:409
    swap_btn.OnClicked(onSwap);              // pages.zig:410
    p_out.header.AddWidget2(swap_btn, 0);    // pages.zig:411

    const output_count = QLabel.New5("0 characters", p_out.panel);  // pages.zig:413
    output_count.SetObjectName("countLabel");// pages.zig:414
    p_out.v.AddWidget2(output_count, 0);     // pages.zig:415
```

The Output panel shows how the `header` field of `Panel` earns its keep: Copy and To
Input buttons are injected into the caption row (right side, past the stretch). The
output pane gets its own object name so QSS can tint it differently
(`QPlainTextEdit#outputPane`).

**Status + assembly.** Lines 417–439:

```zig
    const status = QLabel.New5("", page);    // pages.zig:417
    status.SetObjectName("status");          // pages.zig:418
    parent_layout.AddWidget2(status, 0);     // pages.zig:419
```

The status line is added to the *page* layout, below the Output panel. It starts
empty; `setStatus` swaps its object name between `statusOk`/`statusErr` for color.

```zig
    const form = Form{
        .combo = combo,                      // pages.zig:422
        .keyword_edit = keyword_edit,        // pages.zig:423
        .num1 = num1, .num2 = num2,          // pages.zig:424
        .num1_label = num1_label, .num2_label = num2_label,  // pages.zig:425
        .input = input, .output = output,    // pages.zig:426
        .status = status,                    // pages.zig:427
        .input_count = input_count, .output_count = output_count,  // pages.zig:428
        .copy_btn = copy_btn, .swap_btn = swap_btn,  // pages.zig:429
    };
    updateCipherFields(form);                // pages.zig:436
    combo.OnCurrentIndexChanged(onCipherChanged);  // pages.zig:437
    return form;                             // pages.zig:438
}
```

All the local widget handles are packed into a `Form`. Two finishing touches:
`updateCipherFields(form)` applies the *initial* visibility/labels/ranges (before any
user interaction), and `combo.OnCurrentIndexChanged(onCipherChanged)` makes every
future combo change re-run that logic.

### 3.9 `onCipherChanged` + `updateCipherFields` — lines 441–489

```zig
fn onCipherChanged(self: QComboBox, index: i32) callconv(.c) void {   // pages.zig:441
    const f = if (self.ptr == text_form.combo.ptr) &text_form else &file_form;  // pages.zig:442
    _ = index;                               // pages.zig:443
    updateCipherFields(f.*);                 // pages.zig:444
}
```

Both forms have a combo, both connect this same handler. To know *which* form
changed, it compares `.ptr` of the `self` combo against the two globals
(`[§2.5](ui.md#25-selectnav--lines-85-90)` for the same trick). Default: Text form.

```zig
fn updateCipherFields(f: Form) void {        // pages.zig:447
    const idx = f.combo.CurrentIndex();      // pages.zig:448
    const use_keyword = idx == 3 or idx == 4;  // pages.zig:449  Autokey / Vigenere
    const use_num2 = idx == 2;               // pages.zig:450  Affine only
    const use_num1 = idx != 3 and idx != 4;  // pages.zig:451  everything else
```

A small truth table. Index 3/4 need a keyword; 2 (Affine) needs a second number; all
but 3/4 use the primary number.

```zig
    f.keyword_edit.SetVisible(use_keyword);  // pages.zig:453
    f.num1_label.SetVisible(use_num1);       // pages.zig:454
    f.num1.SetVisible(use_num1);             // pages.zig:455
    f.num2_label.SetVisible(use_num2);       // pages.zig:456
    f.num2.SetVisible(use_num2);             // pages.zig:457
```

Show/hide applied to each key widget.

```zig
    const num1_text = switch (idx) {         // pages.zig:459
        0 => "Shift",                        // pages.zig:460  Caesar
        1 => "key",                          // pages.zig:461  Multiplicative
        2 => "key 1",                        // pages.zig:462  Affine
        5 => "Rails",                        // pages.zig:463  Zigzag
        else => "",                          // pages.zig:464  keyword ciphers
    };
    const num2_text = if (use_num2) "key 2" else "";  // pages.zig:466
    if (num1_text.len != 0) f.num1_label.SetText(num1_text);  // pages.zig:467
    if (num2_text.len != 0) f.num2_label.SetText(num2_text);  // pages.zig:468
```

Labels are relabeled per cipher so "Shift" becomes "key 1" etc.

```zig
    switch (idx) {                           // pages.zig:470
        0 => { f.num1.SetRange(0, 25); f.num1.SetValue(3); },  // pages.zig:471–474
        1 => { f.num1.SetRange(0, 25); f.num1.SetValue(3); },  // pages.zig:475–478
        2 => { f.num1.SetRange(1, 25); f.num1.SetValue(3); },  // pages.zig:479–482
        5 => { f.num1.SetRange(2, 10); f.num1.SetValue(3); },  // pages.zig:483–486
        else => {},                          // pages.zig:487
    }
}
```

Ranges differ per cipher: Affine's `a` must be 1–25 (0 breaks it), Zigzag's rails
2–10, Caesar/Multiplicative 0–25.

### 3.10 `onTitleGlow` — lines 491–496

```zig
fn onTitleGlow(self: QTimer) callconv(.c) void {   // pages.zig:491
    _ = self;                                // pages.zig:492
    glow_phase += 0.18;                      // pages.zig:493
    const pulse = 0.5 + 0.5 * @sin(glow_phase);    // pages.zig:494  smooth 0→1→0
    title_effect.SetBlurRadius(8 + 8 * pulse);     // pages.zig:495
}
```

The timer's callback. `glow_phase` advances by a fixed step each tick; `@sin` turns
that into a smooth 0..1 wave (50ms-ish period); blur swings 8–16px. Result: the glow
breathes. This is the entire animation.

### 3.11 Text handlers — lines 498–514

```zig
fn onTextEncrypt(self: QPushButton) callconv(.c) void {   // pages.zig:498
    _ = self;
    execute(&text_form, .encrypt);           // pages.zig:500
}
fn onTextDecrypt(self: QPushButton) callconv(.c) void {   // pages.zig:503
    _ = self;
    execute(&text_form, .decrypt);           // pages.zig:505
}
fn onTextClear(self: QPushButton) callconv(.c) void {     // pages.zig:508
    _ = self;
    text_form.input.SetPlainText("");        // pages.zig:510
    text_form.output.SetPlainText("");       // pages.zig:511
    updateFormCounts(&text_form);            // pages.zig:512
    setStatus(&text_form, true, "Cleared."); // pages.zig:513
}
```

Thin wrappers. Encrypt/Decrypt just route to `execute` with a `Mode`. Clear empties
both text panes, refreshes counters, and writes a green status.

### 3.12 `onFileOpen` — lines 516–540

```zig
fn onFileOpen(self: QPushButton) callconv(.c) void {
    _ = self;
    const path = QFileDialog.GetOpenFileName4(
        gpa,                                 // pages.zig:518  allocator
        main_win,                            // pages.zig:519  parent dialog
        "Open Text File",                    // pages.zig:520  title
        "",                                  // pages.zig:521  start dir
        "Text files (*.txt);;All files (*)", // pages.zig:522  filter
    );
    if (path.len == 0) return;               // pages.zig:525  user cancelled
    defer gpa.free(path);                    // pages.zig:526
```

`QFileDialog` pops the native open dialog. It returns a heap-allocated string (or an
empty one if cancelled). `gpa.free` on exit via `defer` — Zig-style manual memory
management for the return values.

```zig
    const content = readFile(path) catch |err| {   // pages.zig:528
        setStatus(&file_form, false, "Failed to read file.");  // pages.zig:529
        _ = QMessageBox.Information(main_win, "Open File", @errorName(err));  // pages.zig:530
        return;
    };
    defer gpa.free(content);                 // pages.zig:533

    file_form.input.SetPlainText(content);   // pages.zig:535
    file_form.output.SetPlainText("");       // pages.zig:536
    file_path_label.SetText(path);           // pages.zig:537
    updateFormCounts(&file_form);            // pages.zig:538
    setStatus(&file_form, true, "File loaded.");   // pages.zig:539
}
```

Read the file (`readFile`, section 3.17) and pour it into the File page's input.
Errors get the double feedback: red status line **and** a message box. `defer` frees
the file content when done.

### 3.13 File encrypt/decrypt/save — lines 542–572

```zig
fn onFileEncrypt(self: QPushButton) callconv(.c) void {   // pages.zig:542
    _ = self;
    execute(&file_form, .encrypt);           // pages.zig:544
}
fn onFileDecrypt(self: QPushButton) callconv(.c) void {   // pages.zig:547
    _ = self;
    execute(&file_form, .decrypt);           // pages.zig:549
}
```

Same `execute` path, targeting the File form.

```zig
fn onFileSave(self: QPushButton) callconv(.c) void {      // pages.zig:552
    _ = self;
    const out = file_form.output.ToPlainText(gpa);   // pages.zig:554
    defer gpa.free(out);
    if (out.len == 0) {                      // pages.zig:556
        setStatus(&file_form, false, "Nothing to save. Run encrypt or decrypt first.");  // pages.zig:557
        return;
    }
    const path = QFileDialog.GetSaveFileName3(gpa, main_win, "Save Result", "");  // pages.zig:561
    if (path.len == 0) return;               // pages.zig:562
    defer gpa.free(path);
    writeFile(path, out) catch |err| {       // pages.zig:565
        setStatus(&file_form, false, "Failed to write file.");  // pages.zig:566
        _ = QMessageBox.Information(main_win, "Save File", @errorName(err));  // pages.zig:567
        return;
    };
    file_path_label.SetText(path);           // pages.zig:570
    setStatus(&file_form, true, "Saved.");   // pages.zig:571
}
```

Guards against empty output, opens a save dialog, writes, and reports. `ToPlainText`
retrieves the widget text (allocated by `gpa`), `GetSaveFileName3` is the save
variant of the file dialog.

### 3.14 `execute` — lines 574–592

The shared orchestrator for encrypt/decrypt on **both** pages.

```zig
fn execute(f: *Form, mode: Mode) void {      // pages.zig:574
    const text = f.input.ToPlainText(gpa);   // pages.zig:575
    defer gpa.free(text);
    if (text.len == 0) {                     // pages.zig:577
        setStatus(f, false, "Nothing to process. Enter some text or load a file.");  // pages.zig:578
        return;
    }
    const out = doCipher(f, text, mode) catch |err| {  // pages.zig:582
        setStatus(f, false, "Invalid key or input for the selected cipher.");  // pages.zig:583
        _ = QMessageBox.Information(main_win, "Cipher Error", @errorName(err));  // pages.zig:584
        return;
    };
    defer gpa.free(out);
    f.output.SetPlainText(out);              // pages.zig:589
    updateFormCounts(f);                     // pages.zig:590
    setStatus(f, true, if (mode == .encrypt) "Encrypted." else "Decrypted.");  // pages.zig:591
}
```

Read input → guard empty → run `doCipher` (which may return an error) → fill output →
refresh counts → status. Success/failure both flow through `setStatus`.

### 3.15 `doCipher` — lines 594–651

```zig
fn doCipher(f: *Form, text: []const u8, mode: Mode) ![]u8 {   // pages.zig:594
    const buf = try gpa.alloc(u8, text.len);  // pages.zig:595  output buffer
    errdefer gpa.free(buf);                   // pages.zig:596  free on error only

    switch (f.combo.CurrentIndex()) {         // pages.zig:598  pick cipher by index
```

Allocates an output buffer sized to the input (ciphers never change length). The
`switch` dispatches on the combo's current selection. Each branch builds the cipher
from the form's key widgets and runs encrypt or decrypt.

```zig
        0 => {
            const c = try Cipher(Caesar).init(.{@as(u8, @intCast(f.num1.Value()))});  // pages.zig:600
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),   // pages.zig:602
                .decrypt => try c.decrypt(text, buf),   // pages.zig:603
            }
        },
```

Caesar: read `num1` as the shift. The `@intCast` shrinks `i32`→`u8`. Note the
*first* `switch` picks the cipher; the *inner* `switch (mode)` picks direction.

The other branches follow the same shape:

| Combo index | Cipher | Keys used | Lines |
|---|---|---|---|
| 0 | Caesar | `num1` (shift) | 599–605 |
| 1 | Multiplicative | `num1` (key) | 606–612 |
| 2 | Affine | `num1` (`a`) + `num2` (`b`) | 613–622 |
| 3 | Autokey | `keyword_edit` | 623–631 |
| 4 | Vigenere | `keyword_edit` | 632–640 |
| 5 | Zigzag | `num1` (rails) | 641–647 |

The keyword branches fetch the text with `f.keyword_edit.Text(gpa)` and free it with
`defer`. Branch 5 (Zigzag) passes `gpa` into the cipher because rail-fence builds a
temporary structure:

```zig
        5 => {
            const c = try Cipher(Zigzag).init(.{ gpa, @as(u8, @intCast(f.num1.Value())) });
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        else => unreachable,                 // pages.zig:648  combo has exactly 6 items
    }
    return buf;                              // pages.zig:650
}
```

`else => unreachable` is a Zig assertion: the combo only has indices 0–5, so any
other value is a programming error. On success the filled buffer returns to
`execute`.

### 3.16 Copy / Swap — lines 653–678

```zig
fn onCopy(self: QPushButton) callconv(.c) void {   // pages.zig:653
    const f = if (self.ptr == text_form.copy_btn.ptr) &text_form else &file_form;  // pages.zig:654
    const out = f.output.ToPlainText(gpa);   // pages.zig:655
    defer gpa.free(out);
    if (out.len == 0) {                      // pages.zig:657
        setStatus(f, false, "Nothing to copy. Run encrypt or decrypt first.");
        return;
    }
    const clip = QApplication.Clipboard();   // pages.zig:661
    clip.SetText(out);                       // pages.zig:662
    setStatus(f, true, "Output copied to clipboard.");  // pages.zig:663
}
```

Same `.ptr` dispatch as `onCipherChanged` — but here it tests the **copy button** to
tell Text from File. Copy reads the output pane and pushes it to the system
clipboard (`QApplication.Clipboard()` returns the shared clipboard object).

```zig
fn onSwap(self: QPushButton) callconv(.c) void {   // pages.zig:666
    const f = if (self.ptr == text_form.swap_btn.ptr) &text_form else &file_form;  // pages.zig:667
    const out = f.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) { setStatus(...); return; }
    f.input.SetPlainText(out);               // pages.zig:674
    f.output.SetPlainText("");               // pages.zig:675
    updateFormCounts(f);                     // pages.zig:676
    setStatus(f, true, "Result moved to input.");  // pages.zig:677
}
```

"To Input" moves the result back into the input pane and clears the output — handy
for chained transforms.

### 3.17 Counts, status, file IO — lines 680–722

```zig
fn countWords(s: []const u8) usize {         // pages.zig:680
    var n: usize = 0;
    var in_word = false;
    for (s) |c| {                            // pages.zig:683
        const ws = c == ' ' or c == '\t' or c == '\n' or c == '\r';
        if (ws) { in_word = false; }
        else if (!in_word) { n += 1; in_word = true; }
    }
    return n;
}
```

A tiny state machine: word count = number of whitespace→non-whitespace transitions.

```zig
fn updateFormCounts(f: *Form) void {         // pages.zig:695
    const in_text = f.input.ToPlainText(gpa);  // pages.zig:696
    defer gpa.free(in_text);
    const out_text = f.output.ToPlainText(gpa);  // pages.zig:698
    defer gpa.free(out_text);

    var in_buf: [96]u8 = undefined;          // pages.zig:701  stack buffer for fmt
    const in_s = std.fmt.bufPrint(&in_buf, "{d} characters · {d} words",
        .{ in_text.len, countWords(in_text) }) catch "…";  // pages.zig:702
    f.input_count.SetText(in_s);             // pages.zig:703

    var out_buf: [96]u8 = undefined;
    const out_s = std.fmt.bufPrint(&out_buf, "{d} characters", .{out_text.len}) catch "…";  // pages.zig:706
    f.output_count.SetText(out_s);           // pages.zig:707
}
```

Reads both panes, formats the "N characters · M words" strings (into a stack buffer,
falling back to "…" if formatting fails), and writes them into the count labels.

```zig
fn setStatus(f: *Form, ok: bool, msg: []const u8) void {   // pages.zig:710
    f.status.SetObjectName(if (ok) "statusOk" else "statusErr");  // pages.zig:711
    f.status.SetText(msg);                   // pages.zig:712
}
```

The status switcher: **re-point the object name** (`statusOk` → green, `statusErr` →
red) and set the text. Changing an object name at runtime re-evaluates the QSS rules
— this is how the status line changes color without any palette code.

```zig
fn readFile(path: []const u8) ![]u8 {        // pages.zig:715
    const dir = std.Io.Dir.cwd();
    return try dir.readFileAlloc(io, path, gpa, .unlimited);  // pages.zig:717
}

fn writeFile(path: []const u8, data: []const u8) !void {     // pages.zig:720
    const dir = std.Io.Dir.cwd();
    try dir.writeFile(io, .{ .sub_path = path, .data = data });  // pages.zig:722
}
```

Plain Zig file IO. `io` is the `std.Io` saved in `buildAll`. `.unlimited` = no size
cap on the file read.

---

## 4. The full picture

Everything so far, end to end:

```
BOOT
main() ──► pages.buildAll ──► 4 pages registered in stack (0,1,2,3)
                                    │
IDLE ──► QApplication.Exec()  event loop waits
                                    │
USER clicks "Encrypt" on Text page
        ▼
onTextEncrypt (pages.zig:498)
        │  mode = .encrypt
        ▼
execute(&text_form, .encrypt) (pages.zig:574)
        │  reads input pane
        ▼
doCipher(text_form, text, .encrypt) (pages.zig:594)
        │  switch(combo index) → Cipher(Caesar).init(.{shift})
        │  → cipher.encrypt(text, buf)        ◄── src/cipher.zig
        ▼
result buffer
        │  output.SetPlainText(result)
        │  updateFormCounts  → "12 characters · 3 words"
        │  setStatus(true, "Encrypted.")      → QSS statusOk = green
        ▼
event loop resumes, waiting for the next click
```

### The connections that make it all hold together

| Connection | Mechanism | Where |
|---|---|---|
| Nav button → page | `OnClicked` → `SetCurrentIndex` on the shared stack | main.zig:128 / main.zig:95 |
| Pages ↔ slot numbers | `PageIndex` enum (duplicated) + append order | main.zig:18, pages.zig:36 |
| Form widgets ↔ handlers | `Form` struct + globals `text_form`/`file_form` | pages.zig:48, 69–70 |
| Which form a signal came from | `.ptr` identity comparison | pages.zig:442, 654, 667 |
| Styling | `SetObjectName` ↔ QSS `#name` rules | everywhere → ayu_dark.qss |
| Cipher math | `execute` → `doCipher` → `cipher.zig` | pages.zig:574 → 594 |

And the rule of thumb for reading any new Qt code in this repo: **find the
constructor, find the `SetObjectName`, find the `OnXxx` connection.** Those three
lines tell you what it is, how it looks, and what it does when the user touches it.
