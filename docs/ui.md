# Oh My Crypto — How the UI Is Built

This document walks through the entire graphical user interface of **Oh My Crypto**,
from the Qt 6 concepts up to the specific code in this repo. It assumes you know
*no* Qt, but a little Zig and some general programming.

If you only remember one sentence after reading this: **the whole UI is a tree of
widgets, arranged by layouts, styled by a CSS-like file, and wired together with
callbacks.**

---

## 1. The big picture

```
┌───────────────────────────────────────────────────────────────┐
│  QMainWindow            (the OS window, title bar + content)  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  central QWidget     (a plain container)                │  │
│  │  ┌──────────────────────┬────────────────────────────┐  │  │
│  │  │  sidebar QWidget     │  QStackedWidget            │  │  │
│  │  │  (200px wide)        │  ┌──────────────────────┐  │  │  │
│  │  │  • brand label       │  │ page 0: Home         │  │  │  │
│  │  │  • 4 nav buttons     │  │ page 1: Text         │  │  │  │
│  │  │  • theme toggle      │  │ page 2: File         │  │  │  │
│  │  │  • version label     │  │ page 3: About        │  │  │  │
│  │  │                      │  └──────────────────────┘  │  │  │
│  │  └──────────────────────┴────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

Key idea: Qt apps are built by **nesting widgets inside widgets**. Widgets are the
building blocks (labels, buttons, text areas). **Layouts** decide automatically
where each widget goes and how it stretches when the window resizes. You almost
never place a widget at an exact pixel coordinate.

Two files build the whole UI:

| File | Job |
|---|---|
| `src/main.zig` | Creates the app, the window, loads the font, and starts the loop. |
| `src/pages.zig` | Builds the four pages (Home, Text, File, About) and all click handlers. |
| `src/sidebar.zig` | Builds the sidebar navigation and the page switcher wiring. |
| `src/theme.zig` | Dark/light theme switching + persistence (via `QSettings`). |
| `src/style.zig` | Embeds the QSS stylesheets from `src/themes/` at compile time. |

The cipher math lives in `src/cipher.zig`, and the modern AEAD / KDF / hash math
in `src/modern.zig`. Neither is part of the UI; the UI only calls into them when a
button is clicked.

---

## 2. Qt 6 crash course (everything you need for this repo)

### 2.1 Widgets

A **widget** is any visible element. Everything on screen is a `QWidget` or a
subclass of it:

| Class | What it is |
|---|---|
| `QWidget` | A plain, invisible container. Used as the "root" of a group of things. |
| `QLabel` | Text (and sometimes images). Read-only. |
| `QPushButton` | A clickable button. |
| `QLineEdit` | A one-line text input. |
| `QSpinBox` | A number input with up/down arrows. |
| `QComboBox` | A drop-down list. |
| `QPlainTextEdit` | A multi-line text area. |
| `QMainWindow` | The top-level window. |
| `QStackedWidget` | A container that shows **one** of its child pages at a time. |

You build widgets with constructors. In C++ they look like `new QPushButton(...)`;
through the Zig bindings (section 3) they look like `QPushButton.New5(...)`.

### 2.2 Layouts — automatic arrangement

If you put widgets inside a window with no layout, they stack in the top-left corner
and stay there. **Layouts** manage geometry for you:

- `QHBoxLayout` — arranges children left-to-right.
- `QVBoxLayout` (called `QBoxLayout` in this repo) — arranges children top-to-bottom.
- `QGridLayout` — arranges children in rows/columns.

Two crucial rules:

1. **A layout belongs to a parent widget.** `QBoxLayout.New2(dir, parent)` creates
   the layout and immediately tells `parent` to use it.
2. **Widgets added to a layout are reparented to the widget the layout belongs to.**
   Qt uses the parent/child relationship to know when to destroy widgets (no manual
   `free` needed) and how to draw them.

So this pattern repeats everywhere in the code:

```zig
const page = QWidget.New2();                       // 1. blank container
const v = QBoxLayout.New2(top_to_bottom, page);    // 2. vertical layout inside it
const title = QLabel.New5("Hello", page);          // 3. child widget
v.AddWidget2(title, 0);                            // 4. hand child to the layout
```

The second argument to `AddWidget2` is a **stretch factor**: `0` means "use natural
size", `1` means "absorb extra space when the window grows". `AddStretch()` pushes
everything above it to the top and everything below it to the bottom.

### 2.3 Signals and slots → Zig callbacks

Widgets **emit signals** when things happen (a button is clicked, text changes, a
timer fires). Other code **connects** to those signals.

In C++ this is `connect(button, &QPushButton::clicked, receiver, handler);` — a
machinery-heavy language feature.

In this repo it is simply:

```zig
btn_enc.OnClicked(onTextEncrypt);   // pages.zig:190 → pages.zig:498
```

`OnClicked` takes a function pointer. When the user clicks, Qt runs that function.
The handler looks like:

```zig
fn onTextEncrypt(self: QPushButton) callconv(.c) void {   // pages.zig:498
    _ = self;                                             // "I don't need the arg"
    execute(&text_form, .encrypt);
}
```

Signals used in this repo and the Zig methods that hook them:

| Qt signal | Zig hook | Emitted when |
|---|---|---|
| `clicked` | `OnClicked` | button pressed and released |
| `currentIndexChanged` | `OnCurrentIndexChanged` | a `QComboBox` selection changes |
| `timeout` | `OnTimeout` | a `QTimer` fires |

The `callconv(.c)` is a Zig detail: the callback must use the C calling convention
so Qt's C bridge code can call it. `self` is the widget that emitted the signal
(compare two widgets' `.ptr` to tell them apart — see pages.zig:578).

### 2.4 The event loop

Nothing happens by itself. `QApplication.Exec()` (main.zig:44) starts Qt's **event
loop**: an infinite loop that waits for input (mouse, keyboard, timer ticks),
dispatches the matching signal, and redraws. The program stays alive until the
window closes, then `Exec()` returns and `main()` prints "OK!".

### 2.5 Stylesheets (QSS) — Qt's CSS

Qt has a mini-CSS called **QSS**. It is a string applied once to the whole
application (`src/theme.zig`):

```zig
qapp.SetStyleSheet(themeQss());   // theme.zig:27 — dark or light, chosen at startup
```

There are two stylesheets — `src/themes/ayu_dark.qss` and `src/themes/ayu_light.qss`.
Both are pulled into the binary at compile time via `@embedFile` (src/style.zig):

```zig
pub const dark = @embedFile("themes/ayu_dark.qss");
pub const light = @embedFile("themes/ayu_light.qss");
```

`@embedFile` reads the file during the build and inlines its text into the program —
so the theme ships inside the binary, no external file needed at runtime.

`theme.zig` decides which one to apply: the theme saved in `QSettings`, or the
system color scheme if nothing is saved yet (section 6).

QSS rules look like CSS. A rule has a **selector** (which widgets to style) and
**declarations** (colors, padding, fonts). See section 6 for how selectors work.

---

## 3. How Qt gets into Zig (the bridge)

Qt is a C++ library. Zig cannot call C++ classes directly, so this project uses
[`libqt6zig`](https://github.com/rcalixte/libqt6zig): a thin wrapper layer.

```
┌─────────────────────────────────────────────────────────┐
│  your Zig code (main.zig, pages.zig)                    │
│  calls  QPushButton.New5(...) ,  button.OnClicked(...)  │
├─────────────────────────────────────────────────────────┤
│  libqt6zig .zig modules (one per Qt class)              │
│  → structs + constructors + signal hooks                │
├─────────────────────────────────────────────────────────┤
│  libqt6zig C++ glue (.cpp compiled from Qt headers)     │
│  → extern "C" functions that wrap Qt classes            │
├─────────────────────────────────────────────────────────┤
│  Qt 6 (the real C++ library, installed on the system)   │
└─────────────────────────────────────────────────────────┘
```

### 3.1 The `qt6` import

```zig
const qt6 = @import("libqt6zig");      // main.zig:2
const QWidget = qt6.QWidget;           // main.zig:8 — local alias
```

Every Qt class becomes a Zig struct under one namespace, `qt6`. The code then makes
short local aliases (`const QPushButton = qt6.QPushButton;`) so the call sites are
readable.

### 3.2 Constructors: `New`, `New2`, … `New5`

C++ has *overloaded* constructors — same class, different arguments. The bindings
number them: `New`, `New2`, `New3`, … Each is one C++ constructor:

```zig
QPushButton.New5(text, parent)   // QPushButton(text, parent)  — button with text
QWidget.New2()                   // QWidget()                  — plain container
QLabel.New5("Oh My Crypto", parent)   // QLabel(text, parent)
QBoxLayout.New2(top_to_bottom, sidebar) // QBoxLayout(direction, parent)
```

So when you read `QWidget.New2()` think "make a plain widget", and `X.New5(a, b)`
think "make an X with those constructor arguments".

### 3.3 Methods map 1:1 to Qt

A widget method in the code is exactly the Qt C++ method name:

```zig
title.SetObjectName("title");      // C++: setObjectName("title")
sidebar.SetFixedWidth(200);        // C++: setFixedWidth(200)
combo.CurrentIndex();              // C++: currentIndex()
f.input.SetPlainText(content);     // C++: setPlainText(content)
stack.SetCurrentIndex(2);          // C++: setCurrentIndex(2)
```

If you ever need to know what one does, search the Qt 6 docs for that class and
method.

### 3.4 `build.zig` — telling the linker which Qt classes you use

`build.zig` lists exactly which Qt classes the app needs (build.zig:32–56):

```zig
const required_artifacts = [_][]const u8{
    "qabstractbutton",
    "qapplication",
    "qboxlayout",
    "qclipboard",
    ...
};
```

Each name corresponds to one wrapped module from `libqt6zig`; the loop links each
one into the executable (build.zig:58–60). **If you use a new Qt class, you must add
its artifact here or you get a link error.**

Also relevant:
- `qt6zig.module("libqt6zig")` is imported as the `libqt6zig` name (build.zig:30).
- `configureQtExeRootModule` (build.zig:63) wires up include paths, the C++ runtime,
  and `rpath` so the binary finds Qt on your system.
- The first build compiles the linked subset of the wrapper from C++ source — that
  is why the cold build takes minutes.

---

## 4. The window shell — `src/main.zig`

`main()` (main.zig:14) sets up the app, loads the font and theme, builds the shell,
and starts the loop. It is deliberately small — the pages and sidebar are built by
`pages.buildUi`:

```zig
const qapp = QApplication.New(init.arena.allocator(), &argc, argv);  // main.zig:19
// embedded Rubik font registered with the font database (main.zig:22–24)
_ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik));
QApplication.SetFont(QFont.New6("Rubik", 12));

theme.init(init.gpa, qapp);                   // main.zig:26  apply dark/light QSS

const win = QMainWindow.New2();               // main.zig:28  the OS window
win.SetWindowTitle("Oh My Crypto");
win.SetMinimumSize2(820, 600);
win.Resize(1040, 700);
```

### 4.1 Central widget + root layout

A `QMainWindow` has a single **central widget** — everything visible must hang off
it. Here the central widget is a plain `QWidget` whose layout splits the screen into
**sidebar | content**:

```zig
const root = QWidget.New2();                     // main.zig:34
const root_box = QHBoxLayout.New(root);          // horizontal split
root_box.SetContentsMargins(0, 0, 0, 0);         // no outer padding
root_box.SetSpacing(0);                          // no gap between columns
```

Then the two columns are added by `pages.buildUi` (pages.zig:133), which creates the
`QStackedWidget`, asks the sidebar to build itself into the root, and then builds
all four pages:

```zig
stack = QStackedWidget.New2();
sidebar.init(stack);        // pages.zig:100  sidebar learns which stack to switch
sidebar.build(root_box);    // pages.zig:101  sidebar builds its column
root_box.AddWidget2(stack, 1);
```

Back in `main()`, the whole tree hangs off the window (main.zig:41).

`stack` is a `QStackedWidget` — it holds all four pages but shows only one at a time.
**Navigation = switching which page the stack displays.**

### 4.2 The sidebar — `src/sidebar.zig`

The sidebar moved out of `main.zig` into its own module. `build` (sidebar.zig:33)
fills the column:

```
v = QBoxLayout(top → bottom) inside sidebar
├── brand label    "Oh My Crypto"
├── brand tagline  "ciphers & hashes"
├── (28px spacing)
├── nav button "Home"     → onNavHome
├── nav button "Text"     → onNavText
├── nav button "File"     → onNavFile
├── nav button "About"    → onNavAbout
├── (stretch — pushes version to bottom)
├── theme button "Switch to Light"   → theme.onButtonClicked
└── version label ("v" + config.version)
```

Each nav button is created with `newNav` (sidebar.zig:82), which gives every button
the object name `navBtn` (used by the stylesheet) and makes it **checkable**:

```zig
b.SetObjectName("navBtn");
b.SetCheckable(true);     // button can hold an on/off "checked" state
```

The four handler functions are near-identical; this is `onNavHome` (sidebar.zig:101):

```zig
fn onNavHome(self: QPushButton) callconv(.c) void {
    _ = self;
    selectNav(&nav_home);                                 // light up this button
    stack.SetCurrentIndex(@intFromEnum(PageIndex.home));  // show the page
}
```

`selectNav` (sidebar.zig:90) is the "highlight only the active button" logic. It uses
`.ptr` — the underlying C pointer — to compare against the active button:

```zig
nav_home.SetChecked(nav_home.ptr == active.ptr);
nav_text.SetChecked(nav_text.ptr == active.ptr);
// ... etc
```

The `PageIndex` enum (sidebar.zig:13) gives the four pages stable numbers:

```zig
pub const PageIndex = enum(i32) {
    home = 0, text = 1, file = 2, about = 3,
};
```

The numbers must match the order pages are added to the stack in `pages.buildUi`
(section 5). `@intFromEnum` converts the enum to the integer the stack wants.

The theme button at the bottom is handed to `theme.attachButton` (theme.zig:30), so
`theme.zig` owns its label text and click behavior (section 6).

### 4.3 Why globals?

`nav_home`, `nav_text`, `stack`, … are `var` at module scope (sidebar.zig:24–27). Qt
signal callbacks in this codebase are plain functions with no context pointer, so
the shared UI state lives in globals. Simple, if not elegant. `pages.zig` uses the
same trick for the two forms (section 5.3).

---

## 5. The pages — `src/pages.zig`

### 5.1 `buildUi` — the entry point

```zig
pub fn buildUi(g, app_io, win, root_box) void {   // pages.zig:133
    gpa = g; io = app_io;                         // save allocator + IO for later
    main_win = win;

    stack = QStackedWidget.New2();
    sidebar.init(stack);
    sidebar.build(root_box);
    root_box.AddWidget2(stack, 1);

    buildHome();
    buildText();
    buildFile();
    buildAbout();
    sidebar.selectHome();                         // light up Home in the nav
}
```

`main.zig` calls `buildUi` and only then attaches the root widget to the window.
Each `buildX` function constructs one page and appends it to the stack with
`_ = stack.AddWidget(page);`. The append order **is** the page index (Home=0,
Text=1, File=2, About=3) — matching `PageIndex` in `sidebar.zig`.

### 5.2 Home — layout and the glowing title

`buildHome` (pages.zig:150) builds a column layout:

```
v = QBoxLayout(top → bottom) inside pageHome
├── stretch
├── title QLabel    "Oh My Crypto"   (animated glow)
├── subtitle QLabel "Encrypt, decrypt and hash text with classical and modern algorithms"
├── divider QLabel  (2px tall, gold)
├── (36px spacing)
├── chipsHost QWidget (grid of algorithm-name chips, 3 columns)
├── (12px spacing)
├── note QLabel     "Classical ciphers and modern AEAD encryption with password key derivation\n(not for real data)."
├── stretch
└── footer QLabel   "Educational tool"
```

Two interesting bits.

**Centered chips grid.** The algorithm names (all 11 classical ciphers) are placed
in a `QGridLayout` (pages.zig:203) by computing row/column from the loop index:

```zig
for (ciphers_list, 0..) |name, i| {
    const row: i32 = @intCast(i / 3);   // 0,0,0,1,1,1,2,2,2,3,3
    const col: i32 = @intCast(i % 3);   // 0,1,2,0,1,2,0,1,2,0,1
    const chip = QLabel.New5(name, chips_host);
    chip.SetObjectName("chip");         // styled as a rounded "pill"
    chips.AddWidget2(chip, row, col);
}
```

**The animated glow.** This is the only animation in the app. It has two parts:

```zig
title_effect = QGraphicsDropShadowEffect.New2(page);   // a visual "shadow"
title_effect.SetColor(QColor.New5(0xe6, 0xb4, 0x50)); // gold
title_effect.SetBlurRadius(50);                        // wide soft glow
title.SetGraphicsEffect(title_effect);                 // attach to the title
```

plus a timer that repeatedly changes the blur radius (pages.zig:170):

```zig
title_timer = QTimer.New2(page);
title_timer.SetInterval(80);             // fire every 80 ms
title_timer.OnTimeout(onTitleGlow);      // run this each tick
title_timer.Start(80);
```

```zig
fn onTitleGlow(self: QTimer) callconv(.c) void {   // pages.zig:664
    _ = self;
    glow_phase += 0.18;
    const pulse = 0.5 + 0.5 * @sin(glow_phase);    // smoothly 0 → 1 → 0 → 1 …
    title_effect.SetBlurRadius(8 + 8 * pulse);     // breathing effect
}
```

A timer + changing a style property each tick is the general recipe for Qt
animations.

### 5.3 The shared cipher form — `buildCipherForm`

The Text page (process typed text) and File page (process a file) are almost the
same. The author noticed this and built a **single reusable function**,
`buildCipherForm` (pages.zig:433), called twice — once per page:

```zig
const form = buildCipherForm(page, v, true);   // pages.zig:243  Text: input editable
const form = buildCipherForm(page, v, false);  // pages.zig:307  File: input read-only
```

The form is a stack of panels (see section 5.5 for the `newPanel` helper):

```
"Cipher & Key" panel
├── category QComboBox   [Classical | Modern | Hash]
├── algorithm QComboBox  (repopulated when the category changes)
├── modern row (QHBoxLayout)
│   ├── password QLineEdit (masked; visible only for Modern)
│   └── KDF QComboBox [Argon2id | PBKDF2-SHA256 | scrypt]  (visible only for Modern)
└── key row (QHBoxLayout)
    ├── keyword QLineEdit   (visible for keyword ciphers)
    ├── "Shift"/"key"/"Rails" QLabel + QSpinBox
    └── "key 2" QLabel + QSpinBox   (visible only for Affine)

"Input" panel
├── QPlainTextEdit   (editable on Text page, read-only on File page)
└── count QLabel "0 characters · 0 words"

"Output" panel
├── header: [Copy] [To Input]
├── QPlainTextEdit  (always read-only)
└── count QLabel "0 characters"

status QLabel  (empty / green "statusOk" / red "statusErr")
```

**UI state lives in a struct.** All the widgets the code needs to touch later are
packed into `Form` (pages.zig:98):

```zig
const Form = struct {
    category: QComboBox,
    combo: QComboBox,
    keyword_edit: QLineEdit,
    password_edit: QLineEdit,
    kdf_combo: QComboBox,
    num1: QSpinBox,
    num2: QSpinBox,
    num1_label: QLabel,
    num2_label: QLabel,
    input: QPlainTextEdit,
    output: QPlainTextEdit,
    status: QLabel,
    input_count: QLabel,
    output_count: QLabel,
    copy_btn: QPushButton,
    swap_btn: QPushButton,
    enc_btn: QPushButton = undefined,
    dec_btn: QPushButton = undefined,
    hash_btn: QPushButton = undefined,
};
```

The builder fills one in and returns it, and the caller stores it in a global:
`text_form` (pages.zig:125) and `file_form` (pages.zig:126). The action buttons
(Encrypt / Decrypt / Hash) are created by the pages *after* the form, so the caller
squirrels them into the struct and calls `updateActionButtons`. Handlers look up
which form they belong to by comparing `.ptr`:

```zig
fn onCipherChanged(self: QComboBox, index: i32) callconv(.c) void {
    const f = if (self.ptr == text_form.combo.ptr) &text_form else &file_form;
    _ = index;
    updateCipherFields(f.*);
}
```

The same trick distinguishes the two pages' category combos and buttons.

**Category switching.** `onCategoryChanged` (pages.zig:570) runs
`repopulateAlgorithmCombo` (pages.zig:584), which empties the algorithm combo and
fills it from the matching name array:

| Category | Name array (pages.zig) | Fills combo with |
|---|---|---|
| Classical | `classical_names` (51) | 11 classical ciphers |
| Modern | `modern_names` (65) | 11 AEAD ciphers |
| Hash | `hash_names` (79) | 16 hashes |

`updateActionButtons` (pages.zig:598) then shows Encrypt/Decrypt for Classical and
Modern, or the single **Hash** button for the Hash category.

**Dynamic fields.** Different ciphers need different keys (a shift, a keyword, two
numbers). `updateCipherFields` (pages.zig:605) shows/hides the right widgets based on
the category and the selected combo index:

- category Modern → show password + KDF combo, hide the rest
- category Hash → hide all key inputs
- Classical, keyword ciphers (Autokey, Vigenère, Beaufort, Columnar, Bifid) → keyword edit
- Affine → both spinboxes, labelled "key 1" / "key 2"
- Caesar/Multiplicative → one spinbox, "Shift"/"key"
- Zigzag → one spinbox, "Rails", range 2–10
- Atbash/Rot13 → no key inputs at all

It also re-ranges the spinboxes so the numbers make sense per cipher (e.g. Zigzag
rails can't be 0 or 1).

### 5.4 Click → cipher → screen (the data flow)

Pressing **Encrypt** on the Text page runs `onTextEncrypt` → `execute` → `doCipher`:

```
click ─► onTextEncrypt(pages.zig:671)
          │ execute(&text_form, .encrypt)          read input text (pages.zig:757)
          ▼
        category? Hash ─► doHash(f, text) (pages.zig:789)
                          │  map combo index → modern.HashAlgo
                          │  modern.hash(gpa, algo, text)   ← src/modern.zig
          │ category? Modern ─► doModern(f, text, mode) (pages.zig:916)
          │                     read password + KDF
          │                     modern.encrypt / modern.decrypt   ← src/modern.zig
          ▼
        doCipher(f, text, mode) (pages.zig:812)
          │  switch on combo index → pick one of 11 ciphers
          │  build cipher instance (e.g. Cipher(Caesar).init(...))
          │  cipher.encrypt(text, buf)             ← calls src/cipher.zig
          ▼
        returns result buffer
          │ f.output.SetPlainText(out)             put result on screen
          │ updateFormCounts(f)                    refresh "N characters" labels
          │ setStatus(f, true, "Encrypted.")       green status line
```

The other buttons follow the same shape:

| Button | Handler | Does |
|---|---|---|
| Decrypt | `onTextDecrypt` / `onFileDecrypt` | same path, `mode = .decrypt` |
| Hash | `onTextHash` / `onFileHash` | same path, category must be Hash |
| Clear | `onTextClear` | empties input/output, resets counts |
| Open Text File… | `onFileOpen` | `QFileDialog` → read file → fill input |
| Save Result… | `onFileSave` | save output through `QFileDialog` |
| Copy | `onCopy` | output → system clipboard (`QClipboard`) |
| To Input | `onSwap` | output → input, clears output |

Note the error pattern: user errors (empty input, invalid key, missing password)
both set a red status line and pop a `QMessageBox` (pages.zig:773–781) — the status
line is the quiet feedback, the dialog the loud one.

### 5.5 Reusable panels — `newPanel`

The About page and the cipher form are made of repeated "box with a small gold
caption" sections. `newPanel` (pages.zig:415) encapsulates that look:

```zig
fn newPanel(page, parent_layout, title_text, stretch) Panel {
    const panel = QWidget.New(page);      // a styled container
    panel.SetObjectName("panel");         // rounded dark card (see QSS)
    const pv = QBoxLayout.New2(top_to_bottom, panel);
    // header row: gold caption + (stretch) + anything extra
    const header = QHBoxLayout.New(panel);
    const title = QLabel.New5(title_text, panel);
    title.SetObjectName("panelTitle");
    header.AddWidget2(title, 0);
    header.AddStretch();
    pv.AddLayout2(header, 0);
    parent_layout.AddWidget2(panel, stretch);
    return .{ .panel = panel, .v = pv, .header = header };  // caller keeps filling .v
}
```

It returns a `Panel` struct so the caller can keep adding widgets to the panel's
inner layout. The `header` field is public so the cipher form can inject extra
buttons into the Output panel's header (the Copy / To Input buttons, pages.zig:525).

About uses it for its four sections (pages.zig:344–407): intro, features, warning,
license — each one a `newPanel` call plus a few `QLabel`s. Reuse beats repetition.

---

## 6. Theming — `src/themes/` + `src/theme.zig`

The look comes from two QSS files (dark and light), both embedded at compile time
by `src/style.zig` and applied by `src/theme.zig`. Three selector types matter here:

**1. Type selector** — style every widget of that class:

```css
QWidget {
    background-color: #0b0e14;   /* dark theme app-wide background */
    color: #bfc7d5;              /* default text color */
    font-size: 14px;
}

QPushButton { ... }              /* all buttons share this base */
```

**2. Object-name selector** — style one specific widget. This is why the code calls
`SetObjectName` everywhere: it's how QSS targets a widget, like an `id` in CSS.

```css
QLabel#title { color: #e6e1cf; font-size: 44px; font-weight: 700; }
QPushButton#navBtn { ... }
QWidget#panel { background-color: #161b26; border-radius: 8px; }
```

The chain in Zig: `title.SetObjectName("title")` (pages.zig:119) ↔
`QLabel#title { ... }` (themes/ayu_dark.qss).

**3. Pseudo-states** — style a widget depending on its state, written like CSS:

```css
QPushButton#navBtn:hover { ... }      /* mouse over */
QPushButton#navBtn:checked { ... }    /* the active nav button — gold! */
QPushButton:disabled { ... }
QPlainTextEdit:focus { border: 1px solid #e6b450; }
```

The sidebar "highlight the current page in gold" behavior is pure QSS: the nav
buttons are *checkable*, the code checks exactly one of them (`selectNav`), and the
`:checked` rule paints it gold with a left border.

**Switching themes.** `theme.zig` owns the toggle. On startup (`theme.init`,
theme.zig:24) it reads the saved theme from `QSettings`, falls back to the system
color scheme (`QGuiApplication.StyleHints().ColorScheme()`), and applies the matching
QSS. The sidebar's theme button is attached via `theme.attachButton` (theme.zig:30);
clicking it runs `onButtonClicked` (theme.zig:35), which flips the theme, reapplies
the stylesheet, updates the button label, and persists the choice back to
`QSettings`.

The QSS files are palettes you can tweak freely. The buttons, panels, chips,
scrollbars, dropdowns, spinbox arrows, tooltips, and message boxes are all styled
here.

---

## 7. Adding a new page (mental model)

The pattern to copy for a fifth page:

1. Add an entry to `PageIndex` in `src/sidebar.zig`.
2. Write a `buildFoo()` in pages.zig: create a `QWidget` page, give it an object
   name, build a vertical layout, add widgets, `_ = stack.AddWidget(page);` at the end.
3. Call it from `buildUi`.
4. Add a nav button in `sidebar.build` + an `onNavFoo` handler calling
   `selectNav(&nav_foo)` and `stack.SetCurrentIndex(...)`.
5. Style it via `SetObjectName` + a rule in `themes/ayu_dark.qss` (and, ideally,
   the light theme too).

---

## 8. Glossary

| Term | Meaning |
|---|---|
| Widget | Any visible UI element; building block of the UI. |
| Layout | Object that automatically positions/resizes child widgets. |
| Signal | An event a widget emits (clicked, text changed, timer fired). |
| Callback | A function you give to a widget to run when a signal fires. |
| Event loop | The `QApplication.Exec()` loop that delivers events forever. |
| QSS | Qt's CSS-like styling language (stylesheets). |
| Object name | `SetObjectName(...)` label used to style one widget from QSS. |
| Checkable button | A button that toggles a checked/unchecked state. |
| `New2` / `New5` | Numbered constructor overloads from the Zig bindings. |
| `callconv(.c)` | Zig calling convention required so C++ bridge code can call back. |
| `.ptr` | Underlying C pointer of a widget; used to compare widget identity. |
| Stretch factor | `AddWidget2(w, 1)` = this widget eats spare space; `0` = natural size. |
