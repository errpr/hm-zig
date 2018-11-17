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
var BitmapMemory: ?*c_void = null;
var BitmapWidth: c_int = 0;
var BitmapHeight: c_int = 0;

fn w32str(comptime string_literal: []u8) []const c_ushort 
{
    var result = []const c_ushort {'a'} ** string_literal.len;
    for (string_literal) |u8char, i| 
    {
        result[i] = c_ushort(u8char);
    }
    return result;
}

fn RenderWeirdGradient(XOffset: u32, YOffset: u32) void
{
    var Pitch: usize = @intCast(usize, BitmapWidth) * 4;
    var Row = @ptrCast([*]u8, BitmapMemory);
    var Y: i32 = 0;
    while (Y < BitmapHeight) 
    {
        var X: i32 = 0;
        var Pixel = @ptrCast([*]u32, @alignCast(4, Row));
        
        while (X < BitmapWidth)
        {
            //Blue
            var Blue = @intCast(u32, @truncate(u8, @intCast(u32, X) + XOffset));
            var Green = @intCast(u32, @truncate(u8, @intCast(u32, Y) + YOffset));

            Pixel.* = Green << 8 | Blue;
            Pixel += 1;

            X += 1;
        }
        Row += Pitch;
        Y += 1;
    }
}

fn Win32ResizeDIBSection(Width: c_int, Height: c_int) void 
{
    if(BitmapMemory != null) 
    {
        const result = w32f.VirtualFree(BitmapMemory, 0, w32c.MEM_RELEASE);
        if (result == 0) 
        {
            const errorcode = w32f.GetLastError();
            w32f.OutputDebugStringA(c"VirtualFree of BitmapMemory failed.\n");
        }
    }

    BitmapWidth = Width;
    BitmapHeight = Height;

    BitmapInfo = BITMAPINFO {
        .bmiHeader = BITMAPINFOHEADER {
            .biSize = undefined,
            .biWidth = BitmapWidth,
            .biHeight = -BitmapHeight,
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
    const BitmapMemorySize = @intCast(c_ulonglong, (BitmapWidth * BitmapHeight)) * 4;
    BitmapMemory = w32f.VirtualAlloc(null, BitmapMemorySize, w32c.MEM_COMMIT, w32c.PAGE_READWRITE);
}

fn Win32UpdateWindow(DeviceContext: HDC, ClientRect: *const RECT) void 
{
    const WindowWidth = ClientRect.right - ClientRect.left;
    const WindowHeight = ClientRect.bottom - ClientRect.top;
    const result = w32f.StretchDIBits(
        DeviceContext,
        0, 0, BitmapWidth, BitmapHeight,
        0, 0, WindowWidth, WindowHeight,
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
            var ClientRect = RECT {
                .left = 0,
                .right = 0,
                .top = 0,
                .bottom = 0,
            };

            
            var Paint = PAINTSTRUCT {
                .hdc = null,
                .fErase = BOOL(0),
                .rcPaint = undefined,
                .fRestore = BOOL(0),
                .fIncUpdate = BOOL(0),
                .rgbReserved = []u8 {0} ** 32,
            };

            var DeviceContext = w32f.BeginPaint(Window, &Paint);
            const ignored = w32f.GetClientRect(Window, &ClientRect);
            Win32UpdateWindow(DeviceContext, &ClientRect);
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
        const Window = 
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

        if (Window != null) 
        {
            Running = true;
            var XOffset: u32 = 0;
            var YOffset: u32 = 0;
            while(Running) {
                var Message: MSG = undefined;
                var MessageResult: BOOL = w32f.PeekMessageW(LPMSG(&Message), null, UINT(0), UINT(0), w32c.PM_REMOVE);

                while (MessageResult != 0)
                {
                    // why not handle this in the callback?
                    if (Message.message == w32c.WM_QUIT)
                    {
                        Running = false;
                    }

                    const ignored1 = w32f.TranslateMessage(&Message);
                    const ignored2 = w32f.DispatchMessageW(&Message);
                    MessageResult = w32f.PeekMessageW(LPMSG(&Message), null, UINT(0), UINT(0), w32c.PM_REMOVE);
                }
                
                RenderWeirdGradient(XOffset, YOffset);
                const DeviceContext = w32f.GetDC(Window);
                var ClientRect = RECT {
                    .left = 0,
                    .right = 0,
                    .top = 0,
                    .bottom = 0,
                };
                const ignored3 = w32f.GetClientRect(Window, &ClientRect);
                Win32UpdateWindow(DeviceContext, &ClientRect);
                const ignored4 = w32f.ReleaseDC(Window, DeviceContext);
                XOffset = XOffset +% 1;
                YOffset = YOffset +% 1;
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