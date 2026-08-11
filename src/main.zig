const std = @import("std");
const qt6 = @import("libqt6zig");
const pages = @import("pages.zig");
const style = @import("style.zig");
const fonts = @import("assets");

const PageIndex = pages.PageIndex;
const top_to_bottom: i32 = pages.top_to_bottom;

const QApplication = qt6.QApplication;
const QWidget = qt6.QWidget;
const QMainWindow = qt6.QMainWindow;
const QStackedWidget = qt6.QStackedWidget;
const QPushButton = qt6.QPushButton;
const QLabel = qt6.QLabel;
const QBoxLayout = qt6.QBoxLayout;
const QHBoxLayout = qt6.QHBoxLayout;
const QFontDatabase = qt6.QFontDatabase;

var stack: QStackedWidget = undefined;

var nav_home: QPushButton = undefined;
var nav_text: QPushButton = undefined;
var nav_file: QPushButton = undefined;
var nav_about: QPushButton = undefined;

pub fn main(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik));
    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik_italic));

    qapp.SetStyleSheet(style.qss);

    const win = QMainWindow.New2();
    defer win.Delete();
    win.SetWindowTitle("Oh My Crypto");
    win.SetMinimumSize2(820, 600);
    win.Resize(1040, 700);

    const root = QWidget.New2();
    const root_box = QHBoxLayout.New(root);
    root_box.SetContentsMargins(0, 0, 0, 0);
    root_box.SetSpacing(0);

    const sidebar = QWidget.New2();
    sidebar.SetObjectName("sidebar");
    sidebar.SetFixedWidth(200);
    const sv = QBoxLayout.New2(top_to_bottom, sidebar);
    sv.SetContentsMargins(16, 28, 16, 20);
    sv.SetSpacing(4);
    buildSidebar(sidebar, sv);
    root_box.AddWidget2(sidebar, 0);

    stack = QStackedWidget.New2();
    root_box.AddWidget2(stack, 1);

    win.SetCentralWidget(root);

    pages.buildAll(init.gpa, init.io, win, stack);
    selectNav(&nav_home);

    win.Show();

    _ = QApplication.Exec();

    try std.Io.File.stdout().writeStreamingAll(init.io, "OK!\n");
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

fn buildSidebar(parent: QWidget, v: QBoxLayout) void {
    const brand = QLabel.New5("Oh My Crypto", parent);
    brand.SetObjectName("brand");
    v.AddWidget2(brand, 0);

    const tagline = QLabel.New5("classical ciphers", parent);
    tagline.SetObjectName("brandTag");
    v.AddWidget2(tagline, 0);

    v.AddSpacing(28);

    nav_home = newNav(parent, "Home");
    nav_home.OnClicked(onNavHome);
    v.AddWidget2(nav_home, 0);

    nav_text = newNav(parent, "Text");
    nav_text.OnClicked(onNavText);
    v.AddWidget2(nav_text, 0);

    nav_file = newNav(parent, "File");
    nav_file.OnClicked(onNavFile);
    v.AddWidget2(nav_file, 0);

    nav_about = newNav(parent, "About");
    nav_about.OnClicked(onNavAbout);
    v.AddWidget2(nav_about, 0);

    v.AddStretch();

    const version = QLabel.New5("v0.1.0", parent);
    version.SetObjectName("version");
    v.AddWidget2(version, 0);
}

