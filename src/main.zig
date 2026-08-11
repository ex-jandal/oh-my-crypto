const std = @import("std");
const qt6 = @import("libqt6zig");
const pages = @import("pages.zig");
const theme = @import("theme.zig");
const fonts = @import("assets");

const QApplication = qt6.QApplication;
const QWidget = qt6.QWidget;
const QMainWindow = qt6.QMainWindow;
const QHBoxLayout = qt6.QHBoxLayout;
const QFontDatabase = qt6.QFontDatabase;

pub fn main(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    theme.init(init.gpa, qapp);

    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik));
    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik_italic));

    const win = QMainWindow.New2();
    defer win.Delete();
    win.SetWindowTitle("Oh My Crypto");
    win.SetMinimumSize2(820, 600);
    win.Resize(1040, 700);

    const root = QWidget.New2();
    const root_box = QHBoxLayout.New(root);
    root_box.SetContentsMargins(0, 0, 0, 0);
    root_box.SetSpacing(0);

    pages.buildUi(init.gpa, init.io, win, root_box);

    win.SetCentralWidget(root);
    win.Show();

    _ = QApplication.Exec();

    try std.Io.File.stdout().writeStreamingAll(init.io, "OK!\n");
}
