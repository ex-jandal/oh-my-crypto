const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("oh_my_crypto", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "omc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "oh_my_crypto", .module = mod },
            },
        }),
    });
    if (target.result.os.tag == .windows) 
        exe.subsystem = .windows;

    const qt6zig = b.dependency("libqt6zig", .{
        .target = target,
        .optimize = .ReleaseFast,
    });

    const asset_mod = b.createModule(.{
        .root_source_file = b.path("assets/fonts.zig"),
    });
    exe.root_module.addImport("assets", asset_mod);

    // After defining the executable, add the module from the library
    exe.root_module.addImport("libqt6zig", qt6zig.module("libqt6zig"));

    const required_artifacts = [_][]const u8{
        "qabstractbutton",
        "qapplication",
        "qboxlayout",
        "qclipboard",
        "qcolor",
        "qcombobox",
        "qfiledialog",
        "qformlayout",
        "qgridlayout",
        "qgraphicseffect",
        "qguiapplication",
        "qlabel",
        "qlayout",
        "qlineedit",
        "qmainwindow",
        "qmessagebox",
        "qobject",
        "qplaintextedit",
        "qpushbutton",
        "qscrollarea",
        "qsettings",
        "qspinbox",
        "qstackedwidget",
        "qstylehints",
        "qtimer",
        "qvariant",
        "qwidget",
        "qfontdatabase",
    };

    inline for (required_artifacts) |art| {
        exe.root_module.linkLibrary(qt6zig.artifact(art));
    }

    // Use the library-provided convenience method to configure much of the exe
    const configureQtExeRootModule = @import("libqt6zig").configureQtExeRootModule;
    try configureQtExeRootModule(b, exe, .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
