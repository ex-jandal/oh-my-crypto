const std = @import("std");
const config = @import("config");
const qt6 = @import("libqt6zig");
const ciphers = @import("oh_my_crypto").cipher;
const modern = @import("oh_my_crypto").modern;
const sidebar = @import("sidebar.zig");
const i18n = @import("i18n.zig");

const tr = i18n.tr;

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
const QScrollArea = qt6.QScrollArea;
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
const Atbash = ciphers.Atbash;
const Rot13 = ciphers.Rot13;
const Beaufort = ciphers.Beaufort;
const ColumnarTransposition = ciphers.ColumnarTransposition;
const Bifid = ciphers.Bifid;

const align_center: i32 = 132;
pub const top_to_bottom: i32 = 2;

const PageIndex = sidebar.PageIndex;

const Mode = enum {
    encrypt,
    decrypt,
};

const classical_names = [_][:0]const u8{
    "Caesar",
    "Multiplicative",
    "Affine",
    "Autokey",
    "Vigenere",
    "Zigzag",
    "Atbash",
    "Rot13",
    "Beaufort",
    "Columnar Transposition",
    "Bifid",
};

const modern_names = [_][:0]const u8{
    "XChaCha20-Poly1305",
    "ChaCha20-Poly1305",
    "AES-256-GCM",
    "AES-128-GCM",
    "AES-256-GCM-SIV",
    "AES-128-GCM-SIV",
    "AEGIS-256",
    "AEGIS-128L",
    "XSalsa20-Poly1305",
    "XChaCha12-Poly1305",
    "ChaCha12-Poly1305",
};

const hash_names = [_][:0]const u8{
    "SHA-256",
    "SHA-512",
    "SHA3-256",
    "BLAKE3",
    "SHA-1",
    "MD5",
    "SHA-224",
    "SHA-384",
    "SHA-512/256",
    "SHA3-224",
    "SHA3-384",
    "SHA3-512",
    "SHAKE128",
    "SHAKE256",
    "BLAKE2s-256",
    "BLAKE2b-512",
};

fn algoLabel(name: [:0]const u8) []const u8 {
    const translated = tr(name);
    if (std.mem.eql(u8, translated, name)) return name;
    return std.fmt.allocPrint(i18n.allocator(), "{s} - {s}", .{ name, translated }) catch name;
}

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

var io: std.Io = undefined;
var gpa: std.mem.Allocator = undefined;
var main_win: QMainWindow = undefined;
pub var stack: QStackedWidget = undefined;

var text_form: Form = undefined;
var file_form: Form = undefined;
var file_path_label: QLabel = undefined;

var title_effect: QGraphicsDropShadowEffect = undefined;
var title_timer: QTimer = undefined;
var glow_phase: f64 = 0;

pub fn buildUi(g: std.mem.Allocator, app_io: std.Io, win: QMainWindow, root_box: QHBoxLayout) void {
    gpa = g;
    io = app_io;
    main_win = win;

    stack = QStackedWidget.New2();
    sidebar.init(stack);
    sidebar.build(root_box);
    root_box.AddWidget2(stack, 1);

    buildHome();
    buildText();
    buildFile();
    buildAbout();
    sidebar.selectHome();
}

fn buildHome() void {
    const page = QWidget.New2();
    page.SetObjectName("pageHome");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(48, 64, 48, 48);
    v.SetSpacing(16);

    v.AddStretch();

    const title = QLabel.New5(tr("Oh My Crypto"), page);
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
        tr("Encrypt, decrypt and hash text with classical and modern algorithms"),
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
    const ciphers_list = [_][:0]const u8{
        "Caesar",
        "Multiplicative",
        "Affine",
        "Autokey",
        "Vigenere",
        "Zigzag",
        "Atbash",
        "Rot13",
        "Beaufort",
        "Columnar",
        "Bifid",
    };
    for (ciphers_list, 0..) |name, i| {
        const row: i32 = @intCast(i / 3);
        const col: i32 = @intCast(i % 3);
        const chip = QLabel.New5(algoLabel(name), chips_host);
        chip.SetObjectName("chip");
        chip.SetAlignment(align_center);
        chips.AddWidget2(chip, row, col);
    }
    v.AddWidget3(chips_host, 0, align_center);

    v.AddSpacing(12);

    const note = QLabel.New5(
        tr("Classical ciphers and modern AEAD encryption with password key derivation\n(not for real data)."),
        page,
    );
    note.SetObjectName("note");
    note.SetAlignment(align_center);
    v.AddWidget2(note, 0);

    v.AddStretch();

    const footer = QLabel.New5(tr("Educational tool"), page);
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

    const heading = QLabel.New5(tr("Encrypt / Decrypt Text"), page);
    heading.SetObjectName("heading");
    v.AddWidget2(heading, 0);

    const form = buildCipherForm(page, v, true);
    text_form = form;

    const btns = QHBoxLayout.New(page);
    const btn_enc = QPushButton.New5(tr("Encrypt"), page);
    btn_enc.SetObjectName("primaryBtn");
    btn_enc.OnClicked(onTextEncrypt);
    btns.AddWidget2(btn_enc, 1);

    const btn_dec = QPushButton.New5(tr("Decrypt"), page);
    btn_dec.SetObjectName("secondaryBtn");
    btn_dec.OnClicked(onTextDecrypt);
    btns.AddWidget2(btn_dec, 1);

    const btn_hash = QPushButton.New5(tr("Hash"), page);
    btn_hash.SetObjectName("primaryBtn");
    btn_hash.OnClicked(onTextHash);
    btn_hash.SetVisible(false);
    btns.AddWidget2(btn_hash, 1);

    const btn_clear = QPushButton.New5(tr("Clear"), page);
    btn_clear.SetObjectName("ghostBtn");
    btn_clear.OnClicked(onTextClear);
    btns.AddWidget2(btn_clear, 0);
    v.AddLayout2(btns, 0);

    text_form.enc_btn = btn_enc;
    text_form.dec_btn = btn_dec;
    text_form.hash_btn = btn_hash;
    updateActionButtons(text_form);

    _ = stack.AddWidget(page);
}

fn buildFile() void {
    const page = QWidget.New2();
    page.SetObjectName("pageFile");
    const v = QBoxLayout.New2(top_to_bottom, page);
    v.SetContentsMargins(28, 24, 28, 24);
    v.SetSpacing(12);

    const heading = QLabel.New5(tr("Process Text File"), page);
    heading.SetObjectName("heading");
    v.AddWidget2(heading, 0);

    const open_row = QHBoxLayout.New(page);
    const btn_open = QPushButton.New5(tr("Open Text File..."), page);
    btn_open.SetObjectName("primaryBtn");
    btn_open.OnClicked(onFileOpen);
    open_row.AddWidget2(btn_open, 0);

    file_path_label = QLabel.New5(tr("No file selected"), page);
    file_path_label.SetObjectName("status");
    file_path_label.SetWordWrap(true);
    open_row.AddWidget2(file_path_label, 1);
    v.AddLayout2(open_row, 0);

    const form = buildCipherForm(page, v, false);
    file_form = form;

    const btns = QHBoxLayout.New(page);
    const btn_enc = QPushButton.New5(tr("Encrypt"), page);
    btn_enc.SetObjectName("primaryBtn");
    btn_enc.OnClicked(onFileEncrypt);
    btns.AddWidget2(btn_enc, 1);

    const btn_dec = QPushButton.New5(tr("Decrypt"), page);
    btn_dec.SetObjectName("secondaryBtn");
    btn_dec.OnClicked(onFileDecrypt);
    btns.AddWidget2(btn_dec, 1);

    const btn_hash = QPushButton.New5(tr("Hash"), page);
    btn_hash.SetObjectName("primaryBtn");
    btn_hash.OnClicked(onFileHash);
    btn_hash.SetVisible(false);
    btns.AddWidget2(btn_hash, 1);
    v.AddLayout2(btns, 0);

    file_form.enc_btn = btn_enc;
    file_form.dec_btn = btn_dec;
    file_form.hash_btn = btn_hash;
    updateActionButtons(file_form);

    const save_row = QHBoxLayout.New(page);
    const btn_save = QPushButton.New5(tr("Save Result..."), page);
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

    const heading = QLabel.New5(tr("About"), page);
    heading.SetObjectName("heading");
    v.AddWidget2(heading, 0);

    v.AddSpacing(4);

    const p_intro = newPanel(page, v, tr("Oh My Crypto"), 0);
    const badge = QLabel.New5("v" ++ config.version, p_intro.panel);
    badge.SetObjectName("versionBadge");
    p_intro.header.AddWidget2(badge, 0);

    const intro = QLabel.New5(
        tr("app_description"),
        p_intro.panel,
    );
    intro.SetObjectName("about");
    intro.SetWordWrap(true);
    p_intro.v.AddWidget2(intro, 0);

    const p_feat = newPanel(page, v, tr("Features"), 0);
    const bullets = [_][]const u8{
        tr("•  Eleven classical ciphers: Caesar, Multiplicative, Affine, Autokey, Vigenere, Zigzag, Atbash, Rot13, Beaufort, Columnar, Bifid"),
        tr("•  Eleven modern AEAD algorithms (XChaCha20, ChaCha20, AES-GCM, AEGIS and more) keyed from a password via Argon2id, PBKDF2 or scrypt"),
        tr("•  Sixteen hash algorithms: SHA-1/2/3, SHAKE, BLAKE2, BLAKE3, MD5"),
        tr("•  Encrypt or decrypt typed text, hash it, or process .txt files"),
        tr("•  Copy results or move them back to the input in one click"),
        tr("•  Live char and word counts with a status line"),
    };
    for (bullets) |b| {
        const line = QLabel.New5(b, p_feat.panel);
        line.SetObjectName("aboutLine");
        line.SetWordWrap(true);
        p_feat.v.AddWidget2(line, 0);
    }

    const p_warn = newPanel(page, v, tr("Educational tool"), 0);
    const warn = QLabel.New5(
        tr("These ciphers are trivially breakable with modern frequency analysis — do not use them to protect real data."),
        p_warn.panel,
    );
    warn.SetObjectName("aboutLine");
    warn.SetWordWrap(true);
    p_warn.v.AddWidget2(warn, 0);

    const p_lic = newPanel(page, v, tr("License"), 0);
    const lic_text = std.fmt.allocPrint(
        i18n.allocator(),
        "{s}.\n{s}",
        .{ config.license, tr("Qt is licensed separately (LGPL/GPL/commercial).") },
    ) catch config.license;
    const lic = QLabel.New5(lic_text, p_lic.panel);
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
    const p_cipher = newPanel(page, parent_layout, tr("Cipher & Key"), 0);

    const category = QComboBox.New(p_cipher.panel);
    category.AddItem(tr("Classical"));
    category.AddItem(tr("Modern"));
    category.AddItem(tr("Hash"));
    p_cipher.v.AddWidget2(category, 0);

    const combo = QComboBox.New(p_cipher.panel);
    for (classical_names) |name| {
        combo.AddItem(algoLabel(name));
    }
    p_cipher.v.AddWidget2(combo, 0);

    const modern_row = QHBoxLayout.New(p_cipher.panel);

    const password_edit = QLineEdit.New(p_cipher.panel);
    password_edit.SetPlaceholderText(tr("Password (modern)"));
    password_edit.SetEchoMode(qt6.qlineedit_enums.EchoMode.Normal);
    password_edit.SetClearButtonEnabled(true);
    password_edit.SetVisible(false);
    modern_row.AddWidget2(password_edit, 3);

    const kdf_combo = QComboBox.New(p_cipher.panel);
    kdf_combo.AddItem(algoLabel("Argon2id"));
    kdf_combo.AddItem(algoLabel("PBKDF2-SHA256"));
    kdf_combo.AddItem(algoLabel("scrypt"));
    kdf_combo.SetVisible(false);
    modern_row.AddWidget2(kdf_combo, 1);

    p_cipher.v.AddLayout2(modern_row, 0);

    const key_row = QHBoxLayout.New(p_cipher.panel);

    const keyword_edit = QLineEdit.New(p_cipher.panel);
    keyword_edit.SetPlaceholderText(tr("Keyword (letters only)"));
    keyword_edit.SetVisible(false);
    key_row.AddWidget2(keyword_edit, 3);

    const num1_label = QLabel.New5(tr("Shift"), p_cipher.panel);
    num1_label.SetObjectName("keyLabel");
    key_row.AddWidget2(num1_label, 0);

    const num1 = QSpinBox.New(p_cipher.panel);
    num1.SetRange(0, 25);
    num1.SetValue(3);
    num1.SetFixedHeight(32);
    key_row.AddWidget2(num1, 1);

    const num2_label = QLabel.New5(tr("key 2"), p_cipher.panel);
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

    const scroll_host = QScrollArea.New2();
    scroll_host.SetObjectName("scrollArea");
    scroll_host.SetWidgetResizable(true);

    const scroll_widget = QWidget.New2();
    scroll_widget.SetObjectName("scrollHost");
    const scroll_layout = QBoxLayout.New2(top_to_bottom, scroll_widget);
    scroll_layout.SetContentsMargins(0, 0, 0, 0);
    scroll_layout.SetSpacing(8);
    scroll_host.SetWidget(scroll_widget);

    const p_in = newPanel(scroll_widget, scroll_layout, tr("Input"), 1);
    const input = QPlainTextEdit.New(p_in.panel);
    input.SetPlaceholderText(tr("Type or paste text here..."));
    input.SetReadOnly(!editable_input);
    p_in.v.AddWidget2(input, 1);

    const input_count = QLabel.New5(tr("0 characters"), p_in.panel);
    input_count.SetObjectName("countLabel");
    p_in.v.AddWidget2(input_count, 0);

    const p_out = newPanel(scroll_widget, scroll_layout, tr("Output"), 1);
    const output = QPlainTextEdit.New(p_out.panel);
    output.SetObjectName("outputPane");
    output.SetReadOnly(true);
    output.SetPlaceholderText(tr("Result appears here..."));
    p_out.v.AddWidget2(output, 1);

    const copy_btn = QPushButton.New5(tr("Copy"), p_out.panel);
    copy_btn.SetObjectName("miniBtn");
    copy_btn.OnClicked(onCopy);
    p_out.header.AddWidget2(copy_btn, 0);

    const swap_btn = QPushButton.New5(tr("To Input"), p_out.panel);
    swap_btn.SetObjectName("miniBtn");
    swap_btn.OnClicked(onSwap);
    p_out.header.AddWidget2(swap_btn, 0);

    const output_count = QLabel.New5(tr("0 characters"), p_out.panel);
    output_count.SetObjectName("countLabel");
    p_out.v.AddWidget2(output_count, 0);

    scroll_layout.AddStretch();
    parent_layout.AddWidget2(scroll_host, 1);

    const status = QLabel.New5("", page);
    status.SetObjectName("status");
    parent_layout.AddWidget2(status, 0);

    const form = Form{
        .category = category,
        .combo = combo,
        .keyword_edit = keyword_edit,
        .password_edit = password_edit,
        .kdf_combo = kdf_combo,
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
    category.OnCurrentIndexChanged(onCategoryChanged);
    combo.OnCurrentIndexChanged(onCipherChanged);
    return form;
}

fn onCategoryChanged(self: QComboBox, index: i32) callconv(.c) void {
    const f = if (self.ptr == text_form.category.ptr) &text_form else &file_form;
    _ = index;
    repopulateAlgorithmCombo(f);
    updateCipherFields(f.*);
    updateActionButtons(f.*);
}

fn onCipherChanged(self: QComboBox, index: i32) callconv(.c) void {
    const f = if (self.ptr == text_form.combo.ptr) &text_form else &file_form;
    _ = index;
    updateCipherFields(f.*);
}

fn repopulateAlgorithmCombo(f: *Form) void {
    _ = f.combo.BlockSignals(true);
    defer _ = f.combo.BlockSignals(false);

    f.combo.Clear();
    switch (f.category.CurrentIndex()) {
        0 => for (classical_names) |name| f.combo.AddItem(algoLabel(name)),
        1 => for (modern_names) |name| f.combo.AddItem(algoLabel(name)),
        2 => for (hash_names) |name| f.combo.AddItem(algoLabel(name)),
        else => unreachable,
    }
    f.combo.SetCurrentIndex(0);
}

fn updateActionButtons(f: Form) void {
    const is_hash = f.category.CurrentIndex() == 2;
    f.enc_btn.SetVisible(!is_hash);
    f.dec_btn.SetVisible(!is_hash);
    f.hash_btn.SetVisible(is_hash);
}

fn updateCipherFields(f: Form) void {
    const cat = f.category.CurrentIndex();
    const is_modern = cat == 1;
    const is_hash = cat == 2;

    f.password_edit.SetVisible(is_modern);
    f.kdf_combo.SetVisible(is_modern);

    f.keyword_edit.SetVisible(false);
    f.num1_label.SetVisible(false);
    f.num1.SetVisible(false);
    f.num2_label.SetVisible(false);
    f.num2.SetVisible(false);

    if (is_modern or is_hash) return;

    const idx = f.combo.CurrentIndex();
    const use_keyword = idx == 3 or idx == 4 or idx == 8 or idx == 9 or idx == 10;
    const use_num2 = idx == 2;
    const use_num1 = idx != 3 and idx != 4 and idx != 8 and idx != 9 and idx != 10;

    f.keyword_edit.SetVisible(use_keyword);
    f.num1_label.SetVisible(use_num1);
    f.num1.SetVisible(use_num1);
    f.num2_label.SetVisible(use_num2);
    f.num2.SetVisible(use_num2);

    const num1_text = switch (idx) {
        0 => tr("Shift"),
        1 => tr("key"),
        2 => tr("key 1"),
        5 => tr("Rails"),
        else => "",
    };
    const num2_text = if (use_num2) tr("key 2") else "";
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

fn onTextHash(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&text_form, .encrypt);
}

fn onTextClear(self: QPushButton) callconv(.c) void {
    _ = self;
    text_form.input.SetPlainText("");
    text_form.output.SetPlainText("");
    updateFormCounts(&text_form);
    setStatus(&text_form, true, tr("Cleared."));
}

fn onFileOpen(self: QPushButton) callconv(.c) void {
    _ = self;
    const path = QFileDialog.GetOpenFileName4(
        gpa,
        main_win,
        tr("Open Text File"),
        "",
        "Text files (*.txt);;All files (*)",
    );
    if (path.len == 0) return;
    defer gpa.free(path);

    const content = readFile(path) catch |err| {
        setStatus(&file_form, false, tr("Failed to read file."));
        _ = QMessageBox.Information(main_win, tr("Open File"), @errorName(err));
        return;
    };
    defer gpa.free(content);

    file_form.input.SetPlainText(content);
    file_form.output.SetPlainText("");
    file_path_label.SetText(path);
    updateFormCounts(&file_form);
    setStatus(&file_form, true, tr("File loaded."));
}

fn onFileEncrypt(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&file_form, .encrypt);
}

fn onFileDecrypt(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&file_form, .decrypt);
}

fn onFileHash(self: QPushButton) callconv(.c) void {
    _ = self;
    execute(&file_form, .encrypt);
}

fn onFileSave(self: QPushButton) callconv(.c) void {
    _ = self;
    const out = file_form.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) {
        setStatus(&file_form, false, tr("Nothing to save. Run encrypt or decrypt first."));
        return;
    }

    const path = QFileDialog.GetSaveFileName3(gpa, main_win, tr("Save Result"), "");
    if (path.len == 0) return;
    defer gpa.free(path);

    writeFile(path, out) catch |err| {
        setStatus(&file_form, false, tr("Failed to write file."));
        _ = QMessageBox.Information(main_win, tr("Save File"), @errorName(err));
        return;
    };
    file_path_label.SetText(path);
    setStatus(&file_form, true, tr("Saved."));
}

fn execute(f: *Form, mode: Mode) void {
    const text = f.input.ToPlainText(gpa);
    defer gpa.free(text);
    if (text.len == 0) {
        setStatus(f, false, tr("Nothing to process. Enter some text or load a file."));
        return;
    }

    const is_hash = f.category.CurrentIndex() == 2;
    const out = if (is_hash)
        doHash(f, text) catch |err| {
            setStatus(f, false, tr("Hash failed."));
            _ = QMessageBox.Information(main_win, tr("Crypto Error"), @errorName(err));
            return;
        }
    else
        doCipher(f, text, mode) catch |err| {
            const msg = if (err == error.NoPasswordProvided)
                tr("Enter a password for the selected algorithm.")
            else
                tr("Invalid key or input for the selected algorithm.");
            setStatus(f, false, msg);
            _ = QMessageBox.Information(main_win, tr("Crypto Error"), @errorName(err));
            return;
        };
    defer gpa.free(out);

    f.output.SetPlainText(out);
    updateFormCounts(f);
    setStatus(f, true, if (is_hash) tr("Hashed.") else if (mode == .encrypt) tr("Encrypted.") else tr("Decrypted."));
}

fn doHash(f: *Form, text: []const u8) ![]u8 {
    const algo: modern.HashAlgo = switch (f.combo.CurrentIndex()) {
        0 => .sha256,
        1 => .sha512,
        2 => .sha3_256,
        3 => .blake3,
        4 => .sha1,
        5 => .md5,
        6 => .sha224,
        7 => .sha384,
        8 => .sha512_256,
        9 => .sha3_224,
        10 => .sha3_384,
        11 => .sha3_512,
        12 => .shake128,
        13 => .shake256,
        14 => .blake2s256,
        15 => .blake2b512,
        else => unreachable,
    };
    return modern.hash(gpa, algo, text);
}

fn doCipher(f: *Form, text: []const u8, mode: Mode) ![]u8 {
    if (f.category.CurrentIndex() == 1) {
        return doModern(f, text, mode);
    }

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
        6 => {
            const c = try Cipher(Atbash).init(.{});
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        7 => {
            const c = try Cipher(Rot13).init(.{});
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        8 => {
            const keyword = f.keyword_edit.Text(gpa);
            defer gpa.free(keyword);
            const c = try Cipher(Beaufort).init(.{keyword});
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        9 => {
            const keyword = f.keyword_edit.Text(gpa);
            defer gpa.free(keyword);
            const c = try Cipher(ColumnarTransposition).init(.{ gpa, keyword });
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        10 => {
            const keyword = f.keyword_edit.Text(gpa);
            defer gpa.free(keyword);
            const c = try Cipher(Bifid).init(.{ gpa, keyword });
            switch (mode) {
                .encrypt => try c.encrypt(text, buf),
                .decrypt => try c.decrypt(text, buf),
            }
        },
        else => unreachable,
    }
    return buf;
}

fn doModern(f: *Form, text: []const u8, mode: Mode) ![]u8 {
    const password = f.password_edit.Text(gpa);
    defer gpa.free(password);
    if (password.len == 0) return error.NoPasswordProvided;

    const kdf = switch (f.kdf_combo.CurrentIndex()) {
        0 => modern.Kdf.argon2id,
        1 => modern.Kdf.pbkdf2_sha256,
        2 => modern.Kdf.scrypt,
        else => unreachable,
    };
    const aead = switch (f.combo.CurrentIndex()) {
        0 => modern.Aead.xchacha20_poly1305,
        1 => modern.Aead.chacha20_poly1305,
        2 => modern.Aead.aes256_gcm,
        3 => modern.Aead.aes128_gcm,
        4 => modern.Aead.aes256_gcm_siv,
        5 => modern.Aead.aes128_gcm_siv,
        6 => modern.Aead.aegis256,
        7 => modern.Aead.aegis128l,
        8 => modern.Aead.xsalsa20_poly1305,
        9 => modern.Aead.xchacha12_poly1305,
        10 => modern.Aead.chacha12_poly1305,
        else => unreachable,
    };

    return switch (mode) {
        .encrypt => modern.encrypt(io, gpa, password, text, .{ .kdf = kdf, .aead = aead }),
        .decrypt => modern.decrypt(io, gpa, password, text),
    };
}

fn onCopy(self: QPushButton) callconv(.c) void {
    const f = if (self.ptr == text_form.copy_btn.ptr) &text_form else &file_form;
    const out = f.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) {
        setStatus(f, false, tr("Nothing to copy. Run encrypt or decrypt first."));
        return;
    }
    const clip = QApplication.Clipboard();
    clip.SetText(out);
    setStatus(f, true, tr("Output copied to clipboard."));
}

fn onSwap(self: QPushButton) callconv(.c) void {
    const f = if (self.ptr == text_form.swap_btn.ptr) &text_form else &file_form;
    const out = f.output.ToPlainText(gpa);
    defer gpa.free(out);
    if (out.len == 0) {
        setStatus(f, false, tr("Nothing to move. Run encrypt or decrypt first."));
        return;
    }
    f.input.SetPlainText(out);
    f.output.SetPlainText("");
    updateFormCounts(f);
    setStatus(f, true, tr("Result moved to input."));
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

    const in_s = std.fmt.allocPrint(
        i18n.allocator(),
        "{s} {s} · {s} {s}",
        .{
            std.fmt.allocPrint(i18n.allocator(), "{d}", .{in_text.len}) catch "",
            tr("characters"),
            std.fmt.allocPrint(i18n.allocator(), "{d}", .{countWords(in_text)}) catch "",
            tr("words"),
        },
    ) catch "…";
    f.input_count.SetText(in_s);

    const out_s = std.fmt.allocPrint(
        i18n.allocator(),
        "{s} {s}",
        .{
            std.fmt.allocPrint(i18n.allocator(), "{d}", .{out_text.len}) catch "",
            tr("characters"),
        },
    ) catch "…";
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
