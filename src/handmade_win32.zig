const std = @import("std");
use @import("lib/win32/win32_types.zig");
const w32f = @import("lib/win32/win32_functions.zig");
const w32c = @import("lib/win32/win32_constants.zig");

// #define PATCOPY             (DWORD)0x00F00021 /* dest = pattern                  */
// #define PATPAINT            (DWORD)0x00FB0A09 /* dest = DPSnoo                   */
// #define PATINVERT           (DWORD)0x005A0049 /* dest = pattern XOR dest         */
// #define DSTINVERT           (DWORD)0x00550009 /* dest = (NOT dest)               */
// #define BLACKNESS           (DWORD)0x00000042 /* dest = BLACK                    */
// #define WHITENESS (DWORD)0x00FF0062 /* dest = WHITE                    */
// WHITENESS wasn't in MajorLag's win32 constants! What a slacker.
const WHITENESS: DWORD = 0x00FF0062;

fn w32str(comptime string_literal: []u8) []const c_ushort {
    var result = []const c_ushort {'a'} ** string_literal.len;
    for (string_literal) |u8char, i| {
        result[i] = c_ushort(u8char);
    }
    return result;
}

pub stdcallcc fn MainWindowCallback(Window: HWND,
                                 Message: UINT,
                                 WParam: WPARAM,
                                 LParam: LPARAM) LRESULT
{
    var Result = LRESULT(0);
    switch(Message) {
        w32c.WM_SIZE => {
            w32f.OutputDebugStringA(c"WM_SIZE\n");
        },
        w32c.WM_DESTROY => {
            w32f.OutputDebugStringA(c"WM_DESTROY\n");
        },
        w32c.WM_CLOSE => {
            w32f.OutputDebugStringA(c"WM_CLOSE\n");
        },
        w32c.WM_ACTIVATEAPP => {
            w32f.OutputDebugStringA(c"WM_ACTIVATEAPP\n");
        },
        w32c.WM_PAINT => {
            var Paint = PAINTSTRUCT {
                .hdc = null,
                .fErase = BOOL(0),
                .rcPaint = undefined,
                .fRestore = BOOL(0),
                .fIncUpdate = BOOL(0),
                .rgbReserved = []u8 {0} ** 32,
            };
            var DeviceContext = w32f.BeginPaint(Window, &Paint);
            const X: c_int = Paint.rcPaint.left;
            const Y: c_int = Paint.rcPaint.top;
            const Width: c_int = Paint.rcPaint.right - Paint.rcPaint.left;
            const Height: c_int = Paint.rcPaint.bottom - Paint.rcPaint.top;
            const ignored1 = w32f.PatBlt(DeviceContext, X, Y, Width, Height, WHITENESS);
            const ignored2 = w32f.EndPaint(Window, &Paint);
        },
        else => {
            Result = w32f.DefWindowProcW(Window, Message, WParam, LParam);
        },
    }
    return Result;
}

pub export fn WinMain(Instance: HINSTANCE, 
                      PrevInstance: HINSTANCE, 
                      CommandLine: LPSTR, 
                      ShowCode: c_int) c_int 
{
    //const window_proc = w32f.CallWindowProcW();
    const ClassNamePtr = (comptime w32str(&"HandmadeHeroWindowClass"))[0..].ptr;

    const WindowClass = WNDCLASSW {
        .style = w32c.CS_OWNDC|w32c.CS_VREDRAW|w32c.CS_HREDRAW,
        .lpfnWndProc = MainWindowCallback, //window_proc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = Instance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = ClassNamePtr,
    };

    const atom = w32f.RegisterClassW(&WindowClass);
    if(atom != 0) {
        const WindowHandle = 
            w32f.CreateWindowExW(
                DWORD(0), 
                ClassNamePtr,
                (comptime w32str(&"Handmade Hero"))[0..].ptr,
                @bitCast(DWORD, w32c.WS_OVERLAPPEDWINDOW|w32c.WS_VISIBLE),
                w32c.CW_USEDEFAULT,
                w32c.CW_USEDEFAULT,
                w32c.CW_USEDEFAULT,
                w32c.CW_USEDEFAULT,
                null,
                null,
                Instance,
                null);
        if(WindowHandle != null) {
            var Message: MSG = undefined;
            while(true) {
                const MessageResult = w32f.GetMessageW(LPMSG(&Message), null, UINT(0), UINT(0));
                if (MessageResult > 0) {
                    const ignored1 = w32f.TranslateMessage(&Message);
                    const ignored2 = w32f.DispatchMessageW(&Message);
                } else {
                    break;
                }
            }

        } else {
            const errorcode = w32f.GetLastError();
            w32f.OutputDebugStringA(c"No window handle\n");
        }
    } else {
        const errorcode = w32f.GetLastError();
        w32f.OutputDebugStringA(c"No atom\n");
    }

    return 0;
}