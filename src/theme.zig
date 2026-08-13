const std = @import("std");
const qt6 = @import("libqt6zig");
const style = @import("style.zig");
const i18n = @import("i18n.zig");

const tr = i18n.tr;

const QApplication = qt6.QApplication;
const QGuiApplication = qt6.QGuiApplication;
const QPushButton = qt6.QPushButton;
const QSettings = qt6.QSettings;
const QVariant = qt6.QVariant;

pub const Theme = enum { dark, light };

const settings_org = "oh-my-crypto";
const settings_app = "omc";
const settings_format: i32 = 1; // QSettings.IniFormat
const settings_scope: i32 = 0; // QSettings.UserScope
const color_scheme_light: i32 = 1;
const color_scheme_dark: i32 = 2;

var current_theme: Theme = .dark;
var qapp_ref: QApplication = undefined;
var theme_btn: QPushButton = undefined;

pub fn init(gpa: std.mem.Allocator, qapp: QApplication) void {
    qapp_ref = qapp;
    current_theme = loadSavedTheme(gpa) orelse detectSystemTheme();
    qapp.SetStyleSheet(themeQss());
}

pub fn attachButton(btn: QPushButton) void {
    theme_btn = btn;
    theme_btn.SetText(label());
}

pub fn onButtonClicked(self: QPushButton) callconv(.c) void {
    _ = self;
    applyTheme(if (current_theme == .dark) .light else .dark);
}

pub fn label() []const u8 {
    return switch (current_theme) {
        .dark => tr("Switch to Light"),
        .light => tr("Switch to Dark"),
    };
}

fn themeQss() []const u8 {
    return switch (current_theme) {
        .dark => style.dark,
        .light => style.light,
    };
}

fn detectSystemTheme() Theme {
    return switch (QGuiApplication.StyleHints().ColorScheme()) {
        color_scheme_dark => .dark,
        color_scheme_light => .light,
        else => .dark,
    };
}

fn newSettings() QSettings {
    return QSettings.New11(settings_format, settings_scope, settings_org, settings_app);
}

fn loadSavedTheme(gpa: std.mem.Allocator) ?Theme {
    const settings = newSettings();
    defer settings.Delete();

    const v = settings.Value("theme", QVariant.New24(""));
    const saved = v.ToString(gpa);
    defer gpa.free(saved);

    if (std.mem.eql(u8, saved, "dark")) return .dark;
    if (std.mem.eql(u8, saved, "light")) return .light;
    return null;
}

fn applyTheme(t: Theme) void {
    if (t == current_theme) return;
    current_theme = t;
    qapp_ref.SetStyleSheet(themeQss());
    theme_btn.SetText(label());

    const settings = newSettings();
    defer settings.Delete();
    settings.SetValue("theme", QVariant.New24(if (t == .dark) "dark" else "light"));
    settings.Sync();
}
