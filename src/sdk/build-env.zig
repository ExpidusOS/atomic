const std = @import("std");
const BuildEnv = @This();
const Device = @import("device.zig");
const devices = @import("devices.zig");
const kconsts = @import("../kernel/constants.zig");
const types = @import("../types.zig");

fn sdkPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}

pub const Options = struct {
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    tasking: kconsts.Tasking = .none,
    device: ?Device = null,
};

builder: *std.Build,
options: Options,

pub fn init(builder: *std.Build, options: Options) !*BuildEnv {
    const self = try builder.allocator.create(BuildEnv);
    errdefer builder.allocator.free(self);
    self.* = .{
        .builder = builder,
        .options = options,
    };

    if (self.options.device == null) {
        self.options.device = self.standardDeviceOption();
    }

    if (self.options.device) |device| {
        if (device.target) |target| {
            self.options.target = target;
        }
    }
    return self;
}

pub fn deinit(self: *BuildEnv) void {
    self.builder.allocator.free(self);
}

pub fn addExecutable(self: *BuildEnv, name: []const u8, entrypoint: std.build.LazyPath) *std.Build.Step.Compile {
    const exe = self.builder.addExecutable(.{
        .name = name,
        .root_source_file = entrypoint,
        .target = self.options.target,
        .optimize = self.options.optimize,
        .linkage = .static,
    });

    const options = self.builder.addOptions();

    if (self.options.device) |device| {
        options.addOption(?[]const u8, "device", device.name);

        if (device.linker_script) |linker_script| {
            exe.setLinkerScript(linker_script);
        }
    } else {
        options.addOption(?[]const u8, "device", null);
    }

    exe.addAnonymousModule("atomic", .{
        .source_file = .{
            .path = self.builder.pathJoin(&.{ sdkPath(), "..", "module.zig" }),
        },
        .dependencies = &.{
            .{
                .name = "atomic-options",
                .module = options.createModule(),
            },
        },
    });
    return exe;
}

pub fn standardDeviceOption(self: *BuildEnv) ?Device {
    const option = self.builder.option(types.fields.renameEnum(types.enums.fromDecls(devices), "_", "-"), "device", "The name of the device to build for");

    if (option) |device| {
        inline for (@typeInfo(devices).Struct.decls) |decl| {
            var value = @field(devices, decl.name);
            value.name = std.mem.replaceOwned(u8, self.builder.allocator, decl.name, "_", "-") catch @panic("Out of memory");
            if (std.mem.eql(u8, value.name.?, @tagName(device))) return value;
        }
    }
    return null;
}
