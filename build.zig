const Builder = @import("std").build.Builder;
const builtin = @import("builtin");
pub fn build(b: *Builder) void 
{
    var exe = b.addExecutable("handmade", "src/handmade_win32.zig");
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setVerboseLink(true);
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}