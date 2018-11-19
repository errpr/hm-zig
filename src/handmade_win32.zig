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

const win32_offscreen_buffer = struct 
{
    Info: BITMAPINFO,
    Memory: ?*c_void,
    Width: c_int,
    Height: c_int,
    Pitch: usize,
    BytesPerPixel: c_int,
};

const win32_window_dimension = struct
{
    Width: c_int,
    Height: c_int,
};

// globals
var Running: bool = undefined;
var GlobalBackBuffer = win32_offscreen_buffer {
    .Info = BITMAPINFO {
        .bmiHeader = BITMAPINFOHEADER {
            .biSize = undefined,
            .biWidth = 0,
            .biHeight = 0,
            .biPlanes = 0,
            .biBitCount = 0,
            .biCompression = 0,
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
    },
    .Memory = null,
    .Width = 0,
    .Height = 0,
    .Pitch = 0,
    .BytesPerPixel = 0,
};

fn w32str(comptime string_literal: []u8) []const c_ushort 
{
    var result = []const c_ushort {'a'} ** string_literal.len;
    for (string_literal) |u8char, i| 
    {
        result[i] = c_ushort(u8char);
    }
    return result;
}

fn Win32GetWindowDimension(Window: HWND) win32_window_dimension
{
    var ClientRect = RECT {
        .left = 0,
        .right = 0,
        .top = 0,
        .bottom = 0,
    };
    const ignored = w32f.GetClientRect(Window, &ClientRect);
    return win32_window_dimension {
        .Width = ClientRect.right - ClientRect.left,
        .Height = ClientRect.bottom - ClientRect.top,
    };
}

fn RenderWeirdGradient(Buffer: *win32_offscreen_buffer, XOffset: u32, YOffset: u32) void
{
    var Row = @ptrCast([*]u8, Buffer.Memory);
    var Y: i32 = 0;
    while (Y < Buffer.Height) 
    {
        var X: i32 = 0;
        var Pixel = @ptrCast([*]u32, @alignCast(4, Row));
        
        while (X < Buffer.Width)
        {
            //Blue
            var Blue = @intCast(u32, @truncate(u8, @intCast(u32, X) + XOffset));
            var Green = @intCast(u32, @truncate(u8, @intCast(u32, Y) + YOffset));

            Pixel.* = Green << 8 | Blue;
            Pixel += 1;

            X += 1;
        }
        Row += Buffer.Pitch;
        Y += 1;
    }
}

fn Win32ResizeDIBSection(Buffer: *win32_offscreen_buffer, Width: c_int, Height: c_int) void 
{
    if(Buffer.Memory != null) 
    {
        const result = w32f.VirtualFree(Buffer.Memory, 0, w32c.MEM_RELEASE);
        if (result == 0) 
        {
            const errorcode = w32f.GetLastError();
            w32f.OutputDebugStringA(c"VirtualFree of Buffer.Memory failed.\n");
        }
    }

    Buffer.Width = Width;
    Buffer.Height = Height;
    Buffer.Info.bmiHeader.biWidth = Width;
    Buffer.Info.bmiHeader.biHeight = -Height;
    Buffer.Info.bmiHeader.biPlanes = 1;
    Buffer.Info.bmiHeader.biBitCount = 32;
    Buffer.Info.bmiHeader.biSize = @sizeOf(BITMAPINFOHEADER);
    Buffer.BytesPerPixel = 4;
    Buffer.Pitch = @intCast(usize, Width * Buffer.BytesPerPixel);

    const BufferMemorySize = @intCast(c_ulonglong, (Buffer.Width * Buffer.Height) * Buffer.BytesPerPixel);
    Buffer.Memory = w32f.VirtualAlloc(null, BufferMemorySize, w32c.MEM_COMMIT, w32c.PAGE_READWRITE);
}

fn Win32DisplayBufferInWindow(Buffer: win32_offscreen_buffer, DeviceContext: HDC, Width: c_int, Height: c_int) void 
{
    
    const result = w32f.StretchDIBits(
        DeviceContext,
        0, 0, Width, Height,
        0, 0, Buffer.Width, Buffer.Height,
        Buffer.Memory,
        Buffer.Info,
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

            const Dimension = Win32GetWindowDimension(Window);
            Win32DisplayBufferInWindow(GlobalBackBuffer, 
                                       DeviceContext, 
                                       Dimension.Width,
                                       Dimension.Height);

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
        .style = w32c.CS_HREDRAW | w32c.CS_VREDRAW,
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

    Win32ResizeDIBSection(&GlobalBackBuffer, 1280, 720);

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
                
                RenderWeirdGradient(&GlobalBackBuffer, XOffset, YOffset);
                
                const DeviceContext = w32f.GetDC(Window);
                
                var Dimension = Win32GetWindowDimension(Window);
                Win32DisplayBufferInWindow(GlobalBackBuffer, 
                                           DeviceContext, 
                                           Dimension.Width,
                                           Dimension.Height);

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