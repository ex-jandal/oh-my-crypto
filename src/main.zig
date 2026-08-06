const std = @import("std");
const qt6 = @import("libqt6zig");
const pages = @import("pages.zig");
const style = @import("style.zig");

const QApplication = qt6.QApplication;
const QWidget = qt6.QWidget;
const QMainWindow = qt6.QMainWindow;
const QStackedWidget = qt6.QStackedWidget;

pub fn main(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    qapp.SetStyleSheet(style.qss);

    const win = QMainWindow.New2();
    defer win.Delete();
    win.SetWindowTitle("Oh My Crypto");
    win.SetMinimumSize2(820, 640);
    win.Resize(920, 700);

    const stack = QStackedWidget.New2();
    win.SetCentralWidget(stack);

    pages.buildAll(init.gpa, init.io, win, stack);

    win.Show();

    _ = QApplication.Exec();

    try std.Io.File.stdout().writeStreamingAll(init.io, "OK!\n");
}
