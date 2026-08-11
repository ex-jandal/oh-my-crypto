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
const QGridLayout = qt6.QGridLayout;
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
pub const top_to_bottom: i32 = 2;

pub const PageIndex = enum(i32) {
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
    input_count: QLabel,
    output_count: QLabel,
    copy_btn: QPushButton,
    swap_btn: QPushButton,
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
    v.SetContentsMargins(48, 64, 48, 48);
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
    title_timer.SetInterval(80);
    title_timer.OnTimeout(onTitleGlow);
    title_timer.Start(80);

    const subtitle = QLabel.New5(
        "Encrypt and decrypt text with six classical ciphers",
        page,
    );
    subtitle.SetObjectName("subtitle");
    subtitle.SetAlignment(align_center);
    v.AddWidget2(subtitle, 0);

    const divider = QLabel.New5("", page);
    divider.SetObjectName("divider");
    divider.SetFixedWidth(96);
    divider.SetFixedHeight(2);
    v.AddWidget3(divider, 0, align_center);

    v.AddSpacing(36);

    const chips_host = QWidget.New2();
    chips_host.SetObjectName("chipsHost");
    const chips = QGridLayout.New(chips_host);
    chips.SetHorizontalSpacing(12);
    chips.SetVerticalSpacing(12);
    const ciphers_list = [_][]const u8{
        "Caesar",
        "Multiplicative",
        "Affine",
        "Autokey",
        "Vigenere",
        "Zigzag",
    };
    for (ciphers_list, 0..) |name, i| {
        const row: i32 = @intCast(i / 3);
        const col: i32 = @intCast(i % 3);
        const chip = QLabel.New5(name, chips_host);
        chip.SetObjectName("chip");
        chip.SetAlignment(align_center);
        chips.AddWidget2(chip, row, col);
    }
    v.AddWidget3(chips_host, 0, align_center);

    v.AddSpacing(12);

    const note = QLabel.New5(
        "Classical ciphers for learning cryptography\n(not for real data).",
        page,
    );
    note.SetObjectName("note");
    note.SetAlignment(align_center);
    v.AddWidget2(note, 0);

    v.AddStretch();

    const footer = QLabel.New5("Educational tool", page);
    footer.SetObjectName("footer");
    footer.SetAlignment(align_center);
    v.AddWidget2(footer, 0);

    _ = stack.AddWidget(page);
}

fn buildText() void {
    const page = QWidget.New2();
    page.SetObjectName("pageText");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(28, 24, 28, 24);
    v.SetSpacing(12);

    const heading = QLabel.New5("Encrypt / Decrypt Text", page);
    heading.SetObjectName("heading");
    v.AddWidget2(heading, 0);

    const form = buildCipherForm(page, v, true);
    text_form = form;

    const btns = QHBoxLayout.New(page);
    const btn_enc = QPushButton.New5("Encrypt", page);
    btn_enc.SetObjectName("primaryBtn");
    btn_enc.OnClicked(onTextEncrypt);
    btns.AddWidget2(btn_enc, 1);

    const btn_dec = QPushButton.New5("Decrypt", page);
    btn_dec.SetObjectName("secondaryBtn");
    btn_dec.OnClicked(onTextDecrypt);
    btns.AddWidget2(btn_dec, 1);

    const btn_clear = QPushButton.New5("Clear", page);
    btn_clear.SetObjectName("ghostBtn");
    btn_clear.OnClicked(onTextClear);
    btns.AddWidget2(btn_clear, 0);
    v.AddLayout2(btns, 0);

    _ = stack.AddWidget(page);
}

fn buildFile() void {
    const page = QWidget.New2();
    page.SetObjectName("pageFile");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(28, 24, 28, 24);
    v.SetSpacing(12);

    const heading = QLabel.New5("Process Text File", page);
    heading.SetObjectName("heading");
    v.AddWidget2(heading, 0);

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
    btn_dec.SetObjectName("secondaryBtn");
    btn_dec.OnClicked(onFileDecrypt);
    btns.AddWidget2(btn_dec, 1);
    v.AddLayout2(btns, 0);

    const save_row = QHBoxLayout.New(page);
    const btn_save = QPushButton.New5("Save Result...", page);
    btn_save.SetObjectName("primaryBtn");
    btn_save.OnClicked(onFileSave);
    save_row.AddWidget2(btn_save, 0);
    save_row.AddStretch();
    v.AddLayout2(save_row, 0);

    _ = stack.AddWidget(page);
}

fn buildAbout() void {
    const page = QWidget.New2();
    page.SetObjectName("pageAbout");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(28, 24, 28, 24);
    v.SetSpacing(12);

    const heading = QLabel.New5("About", page);
    heading.SetObjectName("heading");
    v.AddWidget2(heading, 0);

    v.AddSpacing(4);

    const p_intro = newPanel(page, v, "Oh My Crypto", 0);
    const badge = QLabel.New5("v0.1.0", p_intro.panel);
    badge.SetObjectName("versionBadge");
    p_intro.header.AddWidget2(badge, 0);

    const intro = QLabel.New5(
        "A desktop GUI utility for classical ciphers, written in Zig 0.16.0 with Qt 6.",
        p_intro.panel,
    );
    intro.SetObjectName("about");
    intro.SetWordWrap(true);
    p_intro.v.AddWidget2(intro, 0);

    const p_feat = newPanel(page, v, "Features", 0);
    const bullets = [_][]const u8{
        "•  Six classical ciphers: Caesar, Multiplicative, Affine, Autokey, Vigenere, Zigzag",
        "•  Encrypt or decrypt typed text, or process .txt files",
        "•  Copy results or move them back to the input in one click",
        "•  Live char and word counts with a status line",
    };
    for (bullets) |b| {
        const line = QLabel.New5(b, p_feat.panel);
        line.SetObjectName("aboutLine");
        line.SetWordWrap(true);
        p_feat.v.AddWidget2(line, 0);
    }

    const p_warn = newPanel(page, v, "Educational tool", 0);
    const warn = QLabel.New5(
        "These ciphers are trivially breakable with modern frequency analysis — do not use them to protect real data.",
        p_warn.panel,
    );
    warn.SetObjectName("aboutLine");
    warn.SetWordWrap(true);
    p_warn.v.AddWidget2(warn, 0);

    const p_lic = newPanel(page, v, "License", 0);
    const lic = QLabel.New5(
        "MIT License.\nQt is licensed separately (LGPL/GPL/commercial).",
        p_lic.panel,
    );
    lic.SetObjectName("aboutLine");
    lic.SetWordWrap(true);
    p_lic.v.AddWidget2(lic, 0);

    v.AddStretch();

    _ = stack.AddWidget(page);
}

const Panel = struct {
    panel: QWidget,
    v: QBoxLayout,
    header: QHBoxLayout,
};

fn newPanel(page: QWidget, parent_layout: QBoxLayout, title_text: []const u8, stretch: i32) Panel {
    const panel = QWidget.New(page);
    panel.SetObjectName("panel");
    const pv = QBoxLayout.New2(top_to_bottom, panel);
    pv.SetContentsMargins(14, 12, 14, 10);
    pv.SetSpacing(8);

    const header = QHBoxLayout.New(panel);
    const title = QLabel.New5(title_text, panel);
    title.SetObjectName("panelTitle");
    header.AddWidget2(title, 0);
    header.AddStretch();

    pv.AddLayout2(header, 0);
    parent_layout.AddWidget2(panel, stretch);
    return .{ .panel = panel, .v = pv, .header = header };
}

fn buildCipherForm(page: QWidget, parent_layout: QBoxLayout, editable_input: bool) Form {
    const p_cipher = newPanel(page, parent_layout, "Cipher & Key", 0);

    const combo = QComboBox.New(p_cipher.panel);
    combo.AddItem("Caesar");
    combo.AddItem("Multiplicative");
    combo.AddItem("Affine");
    combo.AddItem("Autokey");
    combo.AddItem("Vigenere");
    combo.AddItem("Zigzag");
    p_cipher.v.AddWidget2(combo, 0);

    const key_row = QHBoxLayout.New(p_cipher.panel);

    const keyword_edit = QLineEdit.New(p_cipher.panel);
    keyword_edit.SetPlaceholderText("Keyword (letters only)");
    keyword_edit.SetVisible(false);
    key_row.AddWidget2(keyword_edit, 3);

    const num1_label = QLabel.New5("Shift", p_cipher.panel);
    num1_label.SetObjectName("keyLabel");
    key_row.AddWidget2(num1_label, 0);

    const num1 = QSpinBox.New(p_cipher.panel);
    num1.SetRange(0, 25);
    num1.SetValue(3);
    num1.SetFixedHeight(32);
    key_row.AddWidget2(num1, 1);

    const num2_label = QLabel.New5("key 2", p_cipher.panel);
    num2_label.SetObjectName("keyLabel");
    num2_label.SetVisible(false);
    key_row.AddWidget2(num2_label, 0);

    const num2 = QSpinBox.New(p_cipher.panel);
    num2.SetRange(0, 25);
    num2.SetValue(9);
    num2_label.SetVisible(false);
    num2.SetFixedHeight(32);
    key_row.AddWidget2(num2, 1);

    p_cipher.v.AddLayout2(key_row, 0);

    const p_in = newPanel(page, parent_layout, "Input", 1);
    const input = QPlainTextEdit.New(p_in.panel);
    input.SetPlaceholderText("Type or paste text here...");
    input.SetReadOnly(!editable_input);
    p_in.v.AddWidget2(input, 1);

    const input_count = QLabel.New5("0 characters", p_in.panel);
    input_count.SetObjectName("countLabel");
    p_in.v.AddWidget2(input_count, 0);

    const p_out = newPanel(page, parent_layout, "Output", 1);
    const output = QPlainTextEdit.New(p_out.panel);
    output.SetObjectName("outputPane");
    output.SetReadOnly(true);
    output.SetPlaceholderText("Result appears here...");
    p_out.v.AddWidget2(output, 1);

    const copy_btn = QPushButton.New5("Copy", p_out.panel);
    copy_btn.SetObjectName("miniBtn");
    copy_btn.OnClicked(onCopy);
    p_out.header.AddWidget2(copy_btn, 0);

    const swap_btn = QPushButton.New5("To Input", p_out.panel);
    swap_btn.SetObjectName("miniBtn");
    swap_btn.OnClicked(onSwap);
    p_out.header.AddWidget2(swap_btn, 0);

    const output_count = QLabel.New5("0 characters", p_out.panel);
    output_count.SetObjectName("countLabel");
    p_out.v.AddWidget2(output_count, 0);

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
        .input_count = input_count,
        .output_count = output_count,
        .copy_btn = copy_btn,
        .swap_btn = swap_btn,
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
    glow_phase += 0.18;
    const pulse = 0.5 + 0.5 * @sin(glow_phase);
    title_effect.SetBlurRadius(8 + 8 * pulse);
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
    updateFormCounts(&text_form);
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
    updateFormCounts(&file_form);
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
    updateFormCounts(f);
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

fn onCopy(self: QPushButton) callconv(.c) void {
    const f = if (self.ptr == text_form.copy_btn.ptr) &text_form else &file_form;
    const out = f.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) {
        setStatus(f, false, "Nothing to copy. Run encrypt or decrypt first.");
        return;
    }
    const clip = QApplication.Clipboard();
    clip.SetText(out);
    setStatus(f, true, "Output copied to clipboard.");
}

fn onSwap(self: QPushButton) callconv(.c) void {
    const f = if (self.ptr == text_form.swap_btn.ptr) &text_form else &file_form;
    const out = f.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) {
        setStatus(f, false, "Nothing to move. Run encrypt or decrypt first.");
        return;
    }
    f.input.SetPlainText(out);
    f.output.SetPlainText("");
    updateFormCounts(f);
    setStatus(f, true, "Result moved to input.");
}

fn countWords(s: []const u8) usize {
    var n: usize = 0;
    var in_word = false;
    for (s) |c| {
        const ws = c == ' ' or c == '\t' or c == '\n' or c == '\r';
        if (ws) {
            in_word = false;
        } else if (!in_word) {
            n += 1;
            in_word = true;
        }
    }
    return n;
}

fn updateFormCounts(f: *Form) void {
    const in_text = f.input.ToPlainText(gpa);
    defer gpa.free(in_text);
    const out_text = f.output.ToPlainText(gpa);
    defer gpa.free(out_text);

    var in_buf: [96]u8 = undefined;
    const in_s = std.fmt.bufPrint(&in_buf, "{d} characters · {d} words", .{ in_text.len, countWords(in_text) }) catch "…";
    f.input_count.SetText(in_s);

    var out_buf: [96]u8 = undefined;
    const out_s = std.fmt.bufPrint(&out_buf, "{d} characters", .{out_text.len}) catch "…";
    f.output_count.SetText(out_s);
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
