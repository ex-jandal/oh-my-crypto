const std = @import("std");
const qt6 = @import("libqt6zig");
const ciphers = @import("oh_my_crypto").cipher;

const QApplication = qt6.QApplication;
const QWidget = qt6.QWidget;
const QPushButton = qt6.QPushButton;
const QLabel = qt6.QLabel;
const QLineEdit = qt6.QLineEdit;
const QSpinBox = qt6.QSpinBox;
const QComboBox = qt6.QComboBox;
const QPlainTextEdit = qt6.QPlainTextEdit;
const QGroupBox = qt6.QGroupBox;
const QMainWindow = qt6.QMainWindow;
const QStackedWidget = qt6.QStackedWidget;
const QBoxLayout = qt6.QBoxLayout;
const QHBoxLayout = qt6.QHBoxLayout;
const QFileDialog = qt6.QFileDialog;
const QMessageBox = qt6.QMessageBox;
const QTimer = qt6.QTimer;
const QColor = qt6.QColor;
const QGraphicsDropShadowEffect = qt6.QGraphicsDropShadowEffect;

const Cipher = ciphers.Cipher;
const Caesar = ciphers.Caesar;
const Multiplicative = ciphers.Multiplicative;
const Affine = ciphers.Affine;
const Autokey = ciphers.Autokey;
const Viegener = ciphers.Viegener;
const Zigzag = ciphers.Zigzag;

const align_center: i32 = 132;
const top_to_bottom: i32 = 2;

const PageIndex = enum(i32) {
    home = 0,
    text = 1,
    file = 2,
    about = 3,
};

const Mode = enum {
    encrypt,
    decrypt,
};

const Form = struct {
    combo: QComboBox,
    keyword_edit: QLineEdit,
    num1: QSpinBox,
    num2: QSpinBox,
    num1_label: QLabel,
    num2_label: QLabel,
    input: QPlainTextEdit,
    output: QPlainTextEdit,
    status: QLabel,
};

var io: std.Io = undefined;
var gpa: std.mem.Allocator = undefined;
var main_win: QMainWindow = undefined;
var stack: QStackedWidget = undefined;

var text_form: Form = undefined;
var file_form: Form = undefined;
var file_path_label: QLabel = undefined;

var title_effect: QGraphicsDropShadowEffect = undefined;
var title_timer: QTimer = undefined;
var glow_phase: f64 = 0;
var glow_tick: u32 = 0;

pub fn buildAll(g: std.mem.Allocator, app_io: std.Io, win: QMainWindow, s: QStackedWidget) void {
    gpa = g;
    io = app_io;
    main_win = win;
    stack = s;
    buildHome();
    buildText();
    buildFile();
    buildAbout();
    stack.SetCurrentIndex(@intFromEnum(PageIndex.home));
}

fn buildHome() void {
    const page = QWidget.New2();
    page.SetObjectName("pageHome");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(48, 48, 48, 48);
    v.SetSpacing(16);

    v.AddStretch();

    const title = QLabel.New5("Oh My Crypto", page);
    title.SetObjectName("title");
    title.SetAlignment(align_center);
    v.AddWidget2(title, 0);

    title_effect = QGraphicsDropShadowEffect.New2(page);
    title_effect.SetColor(QColor.New5(0xe6, 0xb4, 0x50));
    title_effect.SetOffset3(0);
    title_effect.SetBlurRadius(50);
    title.SetGraphicsEffect(title_effect);

    title_timer = QTimer.New2(page);
    title_timer.SetInterval(50);
    title_timer.OnTimeout(onTitleGlow);
    title_timer.Start(50);

    const subtitle = QLabel.New5(
        "Encrypt and decrypt text with six classical ciphers",
        page,
    );
    subtitle.SetObjectName("subtitle");
    subtitle.SetAlignment(align_center);
    v.AddWidget2(subtitle, 0);

    v.AddSpacing(24);

    const btn_text = QPushButton.New5("Encrypt / Decrypt Text", page);
    btn_text.SetObjectName("cardBtn");
    btn_text.SetFixedWidth(440);
    btn_text.OnClicked(onHomeToText);
    v.AddWidget3(btn_text, 0, align_center);

    const btn_file = QPushButton.New5("Process Text File", page);
    btn_file.SetObjectName("cardBtn");
    btn_file.SetFixedWidth(440);
    btn_file.OnClicked(onHomeToFile);
    v.AddWidget3(btn_file, 0, align_center);

    const btn_about = QPushButton.New5("About", page);
    btn_about.SetObjectName("cardBtn");
    btn_about.SetFixedWidth(440);
    btn_about.OnClicked(onHomeToAbout);
    v.AddWidget3(btn_about, 0, align_center);

    v.AddStretch();

    _ = stack.AddWidget(page);
}

fn buildText() void {
    const page = QWidget.New2();
    page.SetObjectName("pageText");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(28, 20, 28, 20);
    v.SetSpacing(12);

    const top = QHBoxLayout.New(page);
    const back = QPushButton.New5("← Home", page);
    back.SetObjectName("backBtn");
    back.OnClicked(onBackHome);
    top.AddWidget2(back, 0);

    const heading = QLabel.New5("Encrypt / Decrypt Text", page);
    heading.SetObjectName("heading");
    top.AddWidget2(heading, 1);
    v.AddLayout2(top, 0);

    const form = buildCipherForm(page, v, true);
    text_form = form;

    const btns = QHBoxLayout.New(page);
    const btn_enc = QPushButton.New5("Encrypt", page);
    btn_enc.SetObjectName("primaryBtn");
    btn_enc.OnClicked(onTextEncrypt);
    btns.AddWidget2(btn_enc, 1);

    const btn_dec = QPushButton.New5("Decrypt", page);
    btn_dec.SetObjectName("primaryBtn");
    btn_dec.OnClicked(onTextDecrypt);
    btns.AddWidget2(btn_dec, 1);

    const btn_clear = QPushButton.New5("Clear", page);
    btn_clear.OnClicked(onTextClear);
    btns.AddWidget2(btn_clear, 1);
    v.AddLayout2(btns, 0);

    _ = stack.AddWidget(page);
}

fn buildFile() void {
    const page = QWidget.New2();
    page.SetObjectName("pageFile");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(28, 20, 28, 20);
    v.SetSpacing(12);

    const top = QHBoxLayout.New(page);
    const back = QPushButton.New5("← Home", page);
    back.SetObjectName("backBtn");
    back.OnClicked(onBackHome);
    top.AddWidget2(back, 0);

    const heading = QLabel.New5("Process Text File", page);
    heading.SetObjectName("heading");
    top.AddWidget2(heading, 1);
    v.AddLayout2(top, 0);

    const open_row = QHBoxLayout.New(page);
    const btn_open = QPushButton.New5("Open Text File...", page);
    btn_open.SetObjectName("primaryBtn");
    btn_open.OnClicked(onFileOpen);
    open_row.AddWidget2(btn_open, 0);

    file_path_label = QLabel.New5("No file selected", page);
    file_path_label.SetObjectName("status");
    file_path_label.SetWordWrap(true);
    open_row.AddWidget2(file_path_label, 1);
    v.AddLayout2(open_row, 0);

    const form = buildCipherForm(page, v, false);
    file_form = form;

    const btns = QHBoxLayout.New(page);
    const btn_enc = QPushButton.New5("Encrypt", page);
    btn_enc.SetObjectName("primaryBtn");
    btn_enc.OnClicked(onFileEncrypt);
    btns.AddWidget2(btn_enc, 1);

    const btn_dec = QPushButton.New5("Decrypt", page);
    btn_dec.SetObjectName("primaryBtn");
    btn_dec.OnClicked(onFileDecrypt);
    btns.AddWidget2(btn_dec, 1);
    v.AddLayout2(btns, 0);

    const save_row = QHBoxLayout.New(page);
    const btn_save = QPushButton.New5("Save Result...", page);
    btn_save.SetObjectName("primaryBtn");
    btn_save.OnClicked(onFileSave);
    save_row.AddWidget2(btn_save, 0);

    const hint = QLabel.New5("Save writes the processed output to a new file.", page);
    hint.SetObjectName("status");
    save_row.AddWidget2(hint, 1);
    v.AddLayout2(save_row, 0);

    _ = stack.AddWidget(page);
}

fn buildAbout() void {
    const page = QWidget.New2();
    page.SetObjectName("pageAbout");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(28, 20, 28, 20);
    v.SetSpacing(12);

    const top = QHBoxLayout.New(page);
    const back = QPushButton.New5("← Home", page);
    back.SetObjectName("backBtn");
    back.OnClicked(onBackHome);
    top.AddWidget2(back, 0);

    const heading = QLabel.New5("About", page);
    heading.SetObjectName("heading");
    top.AddWidget2(heading, 1);
    v.AddLayout2(top, 0);

    const box = QGroupBox.New4("Oh My Crypto", page);
    const bv = QBoxLayout.New2(top_to_bottom, box);
    const text = QLabel.New5(
        "A desktop GUI utility written in Zig 0.16.0 with Qt 6.\n\n" ++
            "Supports six classical ciphers: Caesar, Multiplicative, Affine, " ++
            "Autokey, Vigenere, and Zigzag (rail fence).\n\n" ++
            "Educational tool only. These ciphers are trivially breakable with " ++
            "modern frequency analysis — do not use them to protect real data.\n\n" ++
            "MIT License. Qt is licensed separately (LGPL/GPL/commercial).",
        page,
    );
    text.SetObjectName("about");
    text.SetWordWrap(true);
    bv.AddWidget2(text, 0);
    v.AddWidget2(box, 0);

    v.AddStretch();

    _ = stack.AddWidget(page);
}

fn buildCipherForm(page: QWidget, parent_layout: QBoxLayout, editable_input: bool) Form {
    const grp_cipher = QGroupBox.New4("Cipher", page);
    const gv = QBoxLayout.New2(top_to_bottom, grp_cipher);
    gv.SetSpacing(10);

    const combo = QComboBox.New(page);
    combo.AddItem("Caesar");
    combo.AddItem("Multiplicative");
    combo.AddItem("Affine");
    combo.AddItem("Autokey");
    combo.AddItem("Vigenere");
    combo.AddItem("Zigzag");
    gv.AddWidget2(combo, 0);

    const key_row = QHBoxLayout.New(page);

    const keyword_edit = QLineEdit.New(page);
    keyword_edit.SetPlaceholderText("Keyword (letters only)");
    keyword_edit.SetVisible(false);
    key_row.AddWidget2(keyword_edit, 3);

    const num1_label = QLabel.New5("Shift", page);
    num1_label.SetObjectName("keyLabel");
    key_row.AddWidget2(num1_label, 0);

    const num1 = QSpinBox.New(page);
    num1.SetRange(0, 25);
    num1.SetValue(3);
    key_row.AddWidget2(num1, 1);

    const num2_label = QLabel.New5("b", page);
    num2_label.SetObjectName("keyLabel");
    num2_label.SetVisible(false);
    key_row.AddWidget2(num2_label, 0);

    const num2 = QSpinBox.New(page);
    num2.SetRange(0, 25);
    num2.SetValue(9);
    num2_label.SetVisible(false);
    key_row.AddWidget2(num2, 1);

    gv.AddLayout2(key_row, 0);
    parent_layout.AddWidget2(grp_cipher, 0);

    const grp_input = QGroupBox.New4("Input", page);
    const iv = QBoxLayout.New2(top_to_bottom, grp_input);
    const input = QPlainTextEdit.New(page);
    input.SetPlaceholderText("Type or paste text here...");
    input.SetReadOnly(!editable_input);
    iv.AddWidget2(input, 1);
    parent_layout.AddWidget2(grp_input, 1);

    const grp_output = QGroupBox.New4("Output", page);
    const ov = QBoxLayout.New2(top_to_bottom, grp_output);
    const output = QPlainTextEdit.New(page);
    output.SetReadOnly(true);
    output.SetPlaceholderText("Result appears here...");
    ov.AddWidget2(output, 1);
    parent_layout.AddWidget2(grp_output, 1);

    const status = QLabel.New5("", page);
    status.SetObjectName("status");
    parent_layout.AddWidget2(status, 0);

    const form = Form{
        .combo = combo,
        .keyword_edit = keyword_edit,
        .num1 = num1,
        .num2 = num2,
        .num1_label = num1_label,
        .num2_label = num2_label,
        .input = input,
        .output = output,
        .status = status,
    };
    updateCipherFields(form);
    combo.OnCurrentIndexChanged(onCipherChanged);
    return form;
}

fn onCipherChanged(self: QComboBox, index: i32) callconv(.c) void {
    const f = if (self.ptr == text_form.combo.ptr) &text_form else &file_form;
    _ = index;
    updateCipherFields(f.*);
}

fn updateCipherFields(f: Form) void {
    const idx = f.combo.CurrentIndex();
    const use_keyword = idx == 3 or idx == 4;
    const use_num2 = idx == 2;
    const use_num1 = idx != 3 and idx != 4;

    f.keyword_edit.SetVisible(use_keyword);
    f.num1_label.SetVisible(use_num1);
    f.num1.SetVisible(use_num1);
    f.num2_label.SetVisible(use_num2);
    f.num2.SetVisible(use_num2);

    const num1_text = switch (idx) {
        0 => "Shift",
        1 => "key",
        2 => "key 1",
        5 => "Rails",
        else => "",
    };
    const num2_text = if (use_num2) "key 2" else "";
    if (num1_text.len != 0) f.num1_label.SetText(num1_text);
    if (num2_text.len != 0) f.num2_label.SetText(num2_text);

    switch (idx) {
        0 => {
            f.num1.SetRange(0, 25);
            f.num1.SetValue(3);
        },
        1 => {
            f.num1.SetRange(0, 25);
            f.num1.SetValue(3);
        },
        2 => {
            f.num1.SetRange(1, 25);
            f.num1.SetValue(3);
        },
        5 => {
            f.num1.SetRange(2, 10);
            f.num1.SetValue(3);
        },
        else => {},
    }
}

fn onTitleGlow(self: QTimer) callconv(.c) void {
    _ = self;
    glow_phase += 0.35;
    const pulse = 0.5 + 0.5 * @sin(glow_phase);
    title_effect.SetBlurRadius(8 + 14 * pulse);
    glow_tick += 1;
    if (glow_tick % 15 == 0) {
        const colors = [_][3]i32{
            .{ 0xe6, 0xb4, 0x50 },
            .{ 0xff, 0x8f, 0x40 },
            .{ 0x59, 0xc2, 0xff },
            .{ 0xaa, 0xd9, 0x4c },
        };
        const c = colors[(glow_tick / 15) % colors.len];
        title_effect.SetColor(QColor.New5(c[0], c[1], c[2]));
    }
}

fn onHomeToText(self: QPushButton) callconv(.c) void {
    _ = self;
    stack.SetCurrentIndex(@intFromEnum(PageIndex.text));
}

fn onHomeToFile(self: QPushButton) callconv(.c) void {
    _ = self;
    stack.SetCurrentIndex(@intFromEnum(PageIndex.file));
}

fn onHomeToAbout(self: QPushButton) callconv(.c) void {
    _ = self;
    stack.SetCurrentIndex(@intFromEnum(PageIndex.about));
}

fn onBackHome(self: QPushButton) callconv(.c) void {
    _ = self;
    stack.SetCurrentIndex(@intFromEnum(PageIndex.home));
}

fn onTextEncrypt(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&text_form, .encrypt);
}

fn onTextDecrypt(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&text_form, .decrypt);
}

fn onTextClear(self: QPushButton) callconv(.c) void {
    _ = self;
    text_form.input.SetPlainText("");
    text_form.output.SetPlainText("");
    setStatus(&text_form, true, "Cleared.");
}

fn onFileOpen(self: QPushButton) callconv(.c) void {
    _ = self;
    const path = QFileDialog.GetOpenFileName4(
        gpa,
        main_win,
        "Open Text File",
        "",
        "Text files (*.txt);;All files (*)",
    );
    if (path.len == 0) return;
    defer gpa.free(path);

    const content = readFile(path) catch |err| {
        setStatus(&file_form, false, "Failed to read file.");
        _ = QMessageBox.Information(main_win, "Open File", @errorName(err));
        return;
    };
    defer gpa.free(content);

    file_form.input.SetPlainText(content);
    file_form.output.SetPlainText("");
    file_path_label.SetText(path);
    setStatus(&file_form, true, "File loaded.");
}

fn onFileEncrypt(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&file_form, .encrypt);
}

fn onFileDecrypt(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&file_form, .decrypt);
}

fn onFileSave(self: QPushButton) callconv(.c) void {
    _ = self;
    const out = file_form.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) {
        setStatus(&file_form, false, "Nothing to save. Run encrypt or decrypt first.");
        return;
    }

    const path = QFileDialog.GetSaveFileName3(gpa, main_win, "Save Result", "");
    if (path.len == 0) return;
    defer gpa.free(path);

    writeFile(path, out) catch |err| {
        setStatus(&file_form, false, "Failed to write file.");
        _ = QMessageBox.Information(main_win, "Save File", @errorName(err));
        return;
    };
    file_path_label.SetText(path);
    setStatus(&file_form, true, "Saved.");
}

fn execute(f: *Form, mode: Mode) void {
    const text = f.input.ToPlainText(gpa);
    defer gpa.free(text);
    if (text.len == 0) {
        setStatus(f, false, "Nothing to process. Enter some text or load a file.");
        return;
    }

    const out = doCipher(f, text, mode) catch |err| {
        setStatus(f, false, "Invalid key or input for the selected cipher.");
        _ = QMessageBox.Information(main_win, "Cipher Error", @errorName(err));
        return;
    };
    defer gpa.free(out);

    f.output.SetPlainText(out);
    setStatus(f, true, if (mode == .encrypt) "Encrypted." else "Decrypted.");
}

fn doCipher(f: *Form, text: []const u8, mode: Mode) ![]u8 {
    const buf = try gpa.alloc(u8, text.len);
    errdefer gpa.free(buf);

    switch (f.combo.CurrentIndex()) {
        0 => {
            const c = try Cipher(Caesar).init(.{@as(u8, @intCast(f.num1.Value()))});
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        1 => {
            const c = try Cipher(Multiplicative).init(.{@as(u8, @intCast(f.num1.Value()))});
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        2 => {
            const c = try Cipher(Affine).init(.{
                @as(u8, @intCast(f.num1.Value())),
                @as(u8, @intCast(f.num2.Value())),
            });
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        3 => {
            const keyword = f.keyword_edit.Text(gpa);
            defer gpa.free(keyword);
            const c = try Cipher(Autokey).init(.{ gpa, keyword });
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        4 => {
            const keyword = f.keyword_edit.Text(gpa);
            defer gpa.free(keyword);
            const c = try Cipher(Viegener).init(.{keyword});
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        5 => {
            const c = try Cipher(Zigzag).init(.{ gpa, @as(u8, @intCast(f.num1.Value())) });
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        else => unreachable,
    }
    return buf;
}

fn setStatus(f: *Form, ok: bool, msg: []const u8) void {
    f.status.SetObjectName(if (ok) "statusOk" else "statusErr");
    f.status.SetText(msg);
}

fn readFile(path: []const u8) ![]u8 {
    const dir = std.Io.Dir.cwd();
    return try dir.readFileAlloc(io, path, gpa, .unlimited);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const dir = std.Io.Dir.cwd();
    try dir.writeFile(io, .{ .sub_path = path, .data = data });
}
