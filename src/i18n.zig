const std = @import("std");
const qt6 = @import("libqt6zig");

const QApplication = qt6.QApplication;
const QCoreApplication = qt6.QCoreApplication;
const QGuiApplication = qt6.QGuiApplication;
const QTranslator = qt6.QTranslator;
const QSettings = qt6.QSettings;
const QVariant = qt6.QVariant;

pub const Language = enum {
    en,
    ar,
    es,

    pub fn code(self: Language) []const u8 {
        return switch (self) {
            .en => "en",
            .ar => "ar",
            .es => "es",
        };
    }

    pub fn nativeName(self: Language) []const u8 {
        return switch (self) {
            .en => "English",
            .ar => "العربية",
            .es => "Español",
        };
    }

    pub fn isRtl(self: Language) bool {
        return self == .ar;
    }
};

const settings_org = "oh-my-crypto";
const settings_app = "omc";
const settings_format: i32 = 1; // QSettings.IniFormat
const settings_scope: i32 = 0; // QSettings.UserScope
const right_to_left: i32 = 1; // Qt.RightToLeft
const left_to_right: i32 = 0; // Qt.LeftToRight

const ar_qm = @embedFile("i18n/omc_ar.qm");
const es_qm = @embedFile("i18n/omc_es.qm");

var current: Language = .en;
var arena: std.heap.ArenaAllocator = undefined;
var translator: QTranslator = undefined;
var translator_installed = false;

pub var on_language_changed: ?*const fn () void = null;

pub fn selected() Language {
    return current;
}

pub fn init(gpa: std.mem.Allocator) void {
    arena = std.heap.ArenaAllocator.init(gpa);
    current = loadSavedLanguage();
    QGuiApplication.SetLayoutDirection(if (current.isRtl()) right_to_left else left_to_right);
    installTranslator();
}

pub fn setLanguage(lang: Language) void {
    if (lang == current) return;
    removeTranslator();
    current = lang;
    _ = arena.reset(.retain_capacity);
    QGuiApplication.SetLayoutDirection(if (lang.isRtl()) right_to_left else left_to_right);
    installTranslator();
    persist();
}

pub fn tr(key: [:0]const u8) []const u8 {
    return QCoreApplication.Translate(arena.allocator(), "", key);
}

pub fn allocator() std.mem.Allocator {
    return arena.allocator();
}

fn installTranslator() void {
    translator = QTranslator.New();
    const loaded = switch (current) {
        .en => true,
        .ar => translator.Load3(@ptrCast(ar_qm.ptr), @intCast(ar_qm.len)),
        .es => translator.Load3(@ptrCast(es_qm.ptr), @intCast(es_qm.len)),
    };
    if (loaded) {
        _ = QApplication.InstallTranslator(translator);
        translator_installed = true;
    }
}

fn removeTranslator() void {
    if (!translator_installed) return;
    _ = QApplication.RemoveTranslator(translator);
    translator.Delete();
    translator_installed = false;
}

fn newSettings() QSettings {
    return QSettings.New11(settings_format, settings_scope, settings_org, settings_app);
}

fn loadSavedLanguage() Language {
    const settings = newSettings();
    defer settings.Delete();

    const v = settings.Value("language", QVariant.New24(""));
    const saved = v.ToString(arena.allocator());

    if (std.mem.eql(u8, saved, "ar")) return .ar;
    if (std.mem.eql(u8, saved, "es")) return .es;
    return .en;
}

fn persist() void {
    const settings = newSettings();
    defer settings.Delete();
    settings.SetValue("language", QVariant.New24(current.code()));
    settings.Sync();
}
