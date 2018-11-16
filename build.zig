const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("handmade", "src/handmade_win32.zig");
    exe.setBuildMode(b.standardReleaseOptions());
    b.installArtifact(exe);
    b.default_step.dependOn(&exe.step);
}