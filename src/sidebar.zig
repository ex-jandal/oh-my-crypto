const std = @import("std");
const config = @import("config");
const qt6 = @import("libqt6zig");
const theme = @import("theme.zig");

const QWidget = qt6.QWidget;
const QPushButton = qt6.QPushButton;
const QLabel = qt6.QLabel;
const QBoxLayout = qt6.QBoxLayout;
const QHBoxLayout = qt6.QHBoxLayout;
const QStackedWidget = qt6.QStackedWidget;

pub const PageIndex = enum(i32) {
    home = 0,
    text = 1,
    file = 2,
    about = 3,
};

const top_to_bottom: i32 = 2;

var stack: QStackedWidget = undefined;

var nav_home: QPushButton = undefined;
var nav_text: QPushButton = undefined;
var nav_file: QPushButton = undefined;
var nav_about: QPushButton = undefined;

pub fn init(s: QStackedWidget) void {
    stack = s;
}

pub fn build(root_box: QHBoxLayout) void {
    const sidebar = QWidget.New2();
    sidebar.SetObjectName("sidebar");
    sidebar.SetFixedWidth(200);
    const v = QBoxLayout.New2(top_to_bottom, sidebar);
    v.SetContentsMargins(16, 28, 16, 20);
    v.SetSpacing(4);

    const brand = QLabel.New5(config.full_name, sidebar);
    brand.SetObjectName("brand");
    v.AddWidget2(brand, 0);

    const tagline = QLabel.New5("classical ciphers", sidebar);
    tagline.SetObjectName("brandTag");
    v.AddWidget2(tagline, 0);

    v.AddSpacing(28);

    nav_home = newNav(sidebar, "Home");
    nav_home.OnClicked(onNavHome);
    v.AddWidget2(nav_home, 0);

    nav_text = newNav(sidebar, "Text");
    nav_text.OnClicked(onNavText);
    v.AddWidget2(nav_text, 0);

    nav_file = newNav(sidebar, "File");
    nav_file.OnClicked(onNavFile);
    v.AddWidget2(nav_file, 0);

    nav_about = newNav(sidebar, "About");
    nav_about.OnClicked(onNavAbout);
    v.AddWidget2(nav_about, 0);

    v.AddStretch();

    const theme_btn = QPushButton.New5(theme.label(), sidebar);
    theme_btn.SetObjectName("themeBtn");
    theme_btn.OnClicked(theme.onButtonClicked);
    theme.attachButton(theme_btn);
    v.AddWidget2(theme_btn, 0);

    const version = QLabel.New5("v" ++ config.version, sidebar);
    version.SetObjectName("version");
    v.AddWidget2(version, 0);

    root_box.AddWidget2(sidebar, 0);
}

fn newNav(parent: QWidget, text: []const u8) QPushButton {
    const b = QPushButton.New5(text, parent);
    b.SetObjectName("navBtn");
    b.SetCheckable(true);
    b.SetFixedHeight(40);
    return b;
}

fn selectNav(active: *const QPushButton) void {
    nav_home.SetChecked(nav_home.ptr == active.ptr);
    nav_text.SetChecked(nav_text.ptr == active.ptr);
    nav_file.SetChecked(nav_file.ptr == active.ptr);
    nav_about.SetChecked(nav_about.ptr == active.ptr);
}

pub fn selectHome() void {
    selectNav(&nav_home);
}

fn onNavHome(self: QPushButton) callconv(.c) void {
    _ = self;
    selectNav(&nav_home);
    stack.SetCurrentIndex(@intFromEnum(PageIndex.home));
}

fn onNavText(self: QPushButton) callconv(.c) void {
    _ = self;
    selectNav(&nav_text);
    stack.SetCurrentIndex(@intFromEnum(PageIndex.text));
}

fn onNavFile(self: QPushButton) callconv(.c) void {
    _ = self;
    selectNav(&nav_file);
    stack.SetCurrentIndex(@intFromEnum(PageIndex.file));
}

fn onNavAbout(self: QPushButton) callconv(.c) void {
    _ = self;
    selectNav(&nav_about);
    stack.SetCurrentIndex(@intFromEnum(PageIndex.about));
}
