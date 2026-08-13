const std = @import("std");
const qt6 = @import("libqt6zig");
const pages = @import("pages.zig");
const sidebar = @import("sidebar.zig");
const theme = @import("theme.zig");
const i18n = @import("i18n.zig");
const fonts = @import("assets");

const tr = i18n.tr;

const QApplication = qt6.QApplication;
const QWidget = qt6.QWidget;
const QMainWindow = qt6.QMainWindow;
const QHBoxLayout = qt6.QHBoxLayout;
const QFont = qt6.QFont;
const QFontDatabase = qt6.QFontDatabase;

var gpa: std.mem.Allocator = undefined;
var io: std.Io = undefined;
var main_win: QMainWindow = undefined;
var root: QWidget = undefined;
var root_box: QHBoxLayout = undefined;

pub fn main(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik));
    _ = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.rubik_italic));
    QApplication.SetFont(QFont.New6("Rubik", 12));

    const pid = QFontDatabase.AddApplicationFontFromData(@constCast(fonts.panorama));
    const fams = QFontDatabase.ApplicationFontFamilies(init.arena.allocator(), pid);
    if (fams.len == 0 or !std.mem.eql(u8, fams[0], fonts.panorama_family))
        @panic("PanoramaNaskh font family mismatch");

    gpa = init.gpa;
    io = init.io;

    i18n.init(gpa);
    defer i18n.deinit();
    theme.init(gpa, qapp);

    main_win = QMainWindow.New2();
    defer main_win.Delete();
    main_win.SetWindowTitle(tr("Oh My Crypto"));
    main_win.SetMinimumSize2(820, 600);
    main_win.Resize(1040, 700);

    root = QWidget.New2();
    root_box = QHBoxLayout.New(root);
    root_box.SetContentsMargins(0, 0, 0, 0);
    root_box.SetSpacing(0);

    pages.buildUi(gpa, io, main_win, root_box);
    i18n.on_language_changed = &rebuildUi;

    main_win.SetCentralWidget(root);
    main_win.Show();

    _ = QApplication.Exec();

    try std.Io.File.stdout().writeStreamingAll(init.io, "OK!\n");
}

fn rebuildUi() void {
    sidebar.sidebar_widget.Delete();
    pages.stack.Delete();
    pages.buildUi(gpa, io, main_win, root_box);
    main_win.SetWindowTitle(tr("Oh My Crypto"));
}
