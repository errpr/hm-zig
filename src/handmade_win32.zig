const std = @import("std");
const w32t = @import("lib/win32/win32_types.zig");
const w32f = @import("lib/win32/win32_functions.zig");
const w32c = @import("lib/win32/win32_constants.zig");

pub export fn WinMain(hInstance: w32t.HINSTANCE, hPrevInstance: w32t.HINSTANCE, lpCmdLine: w32t.LPSTR, nCmdShow: c_int) c_int {
  const result: c_int = w32f.MessageBoxA(null, c"This is Handmade Hero.", c"Handmade Hero", 
                                         @bitCast(c_uint, w32c.MB_OK|w32c.MB_ICONINFORMATION));
  return 0;
}