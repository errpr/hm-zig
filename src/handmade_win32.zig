const std = @import("std");
use @import("lib/win32/win32_types.zig");
const w32f = @import("lib/win32/win32_functions.zig");
const w32c = @import("lib/win32/win32_constants.zig");

// /* Ternary raster operations */
// #define SRCCOPY             (DWORD)0x00CC0020 /* dest = source                   */
// #define SRCPAINT            (DWORD)0x00EE0086 /* dest = source OR dest           */
// #define SRCAND              (DWORD)0x008800C6 /* dest = source AND dest          */
// #define SRCINVERT           (DWORD)0x00660046 /* dest = source XOR dest          */
// #define SRCERASE            (DWORD)0x00440328 /* dest = source AND (NOT dest )   */
// #define NOTSRCCOPY          (DWORD)0x00330008 /* dest = (NOT source)             */
// #define NOTSRCERASE         (DWORD)0x001100A6 /* dest = (NOT src) AND (NOT dest) */
// #define MERGECOPY           (DWORD)0x00C000CA /* dest = (source AND pattern)     */
// #define MERGEPAINT          (DWORD)0x00BB0226 /* dest = (NOT source) OR dest     */
// #define PATCOPY             (DWORD)0x00F00021 /* dest = pattern                  */
// #define PATPAINT            (DWORD)0x00FB0A09 /* dest = DPSnoo                   */
// #define PATINVERT           (DWORD)0x005A0049 /* dest = pattern XOR dest         */
// #define DSTINVERT           (DWORD)0x00550009 /* dest = (NOT dest)               */
// #define BLACKNESS           (DWORD)0x00000042 /* dest = BLACK                    */
// #define WHITENESS (DWORD)0x00FF0062 /* dest = WHITE                    */
// WHITENESS wasn't in MajorLag's win32 constants! What a slacker.
const WHITENESS: DWORD = 0x00FF0062;
const SRCCOPY: DWORD = 0x00CC0020;

// globals
var Running: bool = undefined;
var BitmapInfo: BITMAPINFO = undefined;
var BitmapMemory: ?*c_void = undefined;
var BitmapHandle: HBITMAP = undefined;
var BitmapDeviceContext: HDC = undefined;

fn w32str(comptime string_literal: []u8) []const c_ushort 
{
    var result = []const c_ushort {'a'} ** string_literal.len;
    for (string_literal) |u8char, i| 
    {
        result[i] = c_ushort(u8char);
    }
    return result;
}

fn Win32ResizeDIBSection(Width: c_int, Height: c_int) void 
{
    if(BitmapHandle != null)
    {
        // @ptrCast(*c_void, @alignCast(@alignOf(*c_void), BitmapHandle))
        // above didn't work, but below does... really makes you think
        const result = w32f.DeleteObject(@ptrCast(*c_void, @alignCast(1, BitmapHandle)));
        if (result == 0) 
        {
            const errorcode = w32f.GetLastError();
            w32f.OutputDebugStringA(c"Delete Bitmap Failed\n");
        }
    }

    if(BitmapDeviceContext == null)
    {
        BitmapDeviceContext = w32f.CreateCompatibleDC(null);
    }

    BitmapInfo = BITMAPINFO {
        .bmiHeader = BITMAPINFOHEADER {
            .biSize = undefined,
            .biWidth = Width,
            .biHeight = Height,
            .biPlanes = 1,
            .biBitCount = 32,
            .biCompression = 0x0000,
            .biSizeImage = 0,
            .biXPelsPerMeter = 0,
            .biYPelsPerMeter = 0,
            .biClrUsed = 0,
            .biClrImportant = 0,
        },
        .bmiColors = [1]RGBQUAD { 
            RGBQUAD {
                .rgbBlue = 0,
                .rgbGreen = 0,
                .rgbRed = 0,
                .rgbReserved = 0,
            }
        },
    };

    BitmapInfo.bmiHeader.biSize = @sizeOf(BITMAPINFOHEADER);
    BitmapHandle = w32f.CreateDIBSection(BitmapDeviceContext, &BitmapInfo, w32c.DIB_RGB_COLORS, &BitmapMemory, null, 0);
}

fn Win32UpdateWindow(DeviceContext: HDC, X: c_int, Y: c_int, Width: c_int, Height: c_int) void 
{
    const result = w32f.StretchDIBits(
        DeviceContext,
        X, Y, Width, Height,
        X, Y, Width, Height,
        BitmapMemory,
        BitmapInfo,
        w32c.DIB_RGB_COLORS,
        SRCCOPY,
    );

    if(result == 0) 
    {
        w32f.OutputDebugStringA(c"StretchDIBits returned 0\n");
    }
}

pub stdcallcc fn Win32MainWindowCallback(Window: HWND,
                                         Message: UINT,
                                         WParam: WPARAM,
                                         LParam: LPARAM) LRESULT
{
    var Result = LRESULT(0);
    switch(Message) {
        w32c.WM_SIZE => {
            var ClientRect = RECT {
                .left = 0,
                .right = 0,
                .top = 0,
                .bottom = 0,
            };
            const ignored = w32f.GetClientRect(Window, &ClientRect);
            const Width = ClientRect.right - ClientRect.left;
            const Height = ClientRect.bottom - ClientRect.top;
            Win32ResizeDIBSection(Width, Height);
        },
        w32c.WM_DESTROY => {
            // crashed?
            Running = false;
        },
        w32c.WM_CLOSE => {
            // closed by user
            Running = false;
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
            Win32UpdateWindow(DeviceContext, X, Y, Width, Height);
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
    const ClassNamePtr = (comptime w32str(&"HandmadeHeroWindowClass"))[0..].ptr;

    const WindowClass = WNDCLASSW {
        .style = 0,
        .lpfnWndProc = Win32MainWindowCallback,
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
    if (atom != 0) 
    {
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

        if (WindowHandle != null) 
        {
            var Message: MSG = undefined;
            Running = true;
            while(Running) {
                const MessageResult = w32f.GetMessageW(LPMSG(&Message), null, UINT(0), UINT(0));
                if (MessageResult > 0) 
                {
                    const ignored1 = w32f.TranslateMessage(&Message);
                    const ignored2 = w32f.DispatchMessageW(&Message);
                } 
                else 
                {
                    break;
                }
            }
        } 
        else 
        {
            const errorcode = w32f.GetLastError();
            w32f.OutputDebugStringA(c"No window handle\n");
        }
    } 
    else 
    {
        const errorcode = w32f.GetLastError();
        w32f.OutputDebugStringA(c"No atom\n");
    }

    return 0;
}