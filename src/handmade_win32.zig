const std = @import("std");
use @import("lib/win32/win32_types.zig");
const w32f = @import("lib/win32/win32_functions.zig");
const w32c = @import("lib/win32/win32_constants.zig");

const SRCCOPY: DWORD = 0x00CC0020;

// wButtons bitmask
const XINPUT_GAMEPAD_DPAD_UP: WORD        = 0x0001;
const XINPUT_GAMEPAD_DPAD_DOWN: WORD      = 0x0002;
const XINPUT_GAMEPAD_DPAD_LEFT: WORD      = 0x0004;
const XINPUT_GAMEPAD_DPAD_RIGHT: WORD     = 0x0008;
const XINPUT_GAMEPAD_START: WORD          = 0x0010;
const XINPUT_GAMEPAD_BACK: WORD           = 0x0020;
const XINPUT_GAMEPAD_LEFT_THUMB: WORD     = 0x0040;
const XINPUT_GAMEPAD_RIGHT_THUMB: WORD    = 0x0080;
const XINPUT_GAMEPAD_LEFT_SHOULDER: WORD  = 0x0100;
const XINPUT_GAMEPAD_RIGHT_SHOULDER: WORD = 0x0200;
const XINPUT_GAMEPAD_A: WORD              = 0x1000;
const XINPUT_GAMEPAD_B: WORD              = 0x2000;
const XINPUT_GAMEPAD_X: WORD              = 0x4000;
const XINPUT_GAMEPAD_Y: WORD              = 0x8000;

const XINPUT_VIBRATION = struct {
  wLeftMotorSpeed: WORD,
  wRightMotorSpeed: WORD,
};

const XINPUT_GAMEPAD = struct {
  wButtons: WORD,
  bLeftTrigger: BYTE,
  bRightTrigger: BYTE,
  sThumbLX: SHORT,
  sThumbLY: SHORT,
  sThumbRX: SHORT,
  sThumbRY: SHORT,
};

const XINPUT_STATE = struct {
  dwPacketNumber: DWORD,
  Gamepad: XINPUT_GAMEPAD,
};

// NOTE - Casey uses a dynamic load for these, but it seems unneeded since xinput1_4 is completely
// ubiquitous these days, and since I don't want to fight with zig to get dll loading yet, here we are.
extern "xinput1_4" stdcallcc fn XInputGetState(dwUserIndex: DWORD, pState: *XINPUT_STATE) DWORD;
extern "xinput1_4" stdcallcc fn XInputSetState(dwUserIndex: DWORD, pVibration: *XINPUT_VIBRATION) DWORD;

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


// global variables, baby
var GlobalRunning: bool = undefined;
var GlobalBackBuffer: win32_offscreen_buffer = undefined;


fn w32str(comptime string_literal: []u8) []const c_ushort 
{
    var result = []const c_ushort {'a'} ** (string_literal.len + 1);
    for (string_literal) |u8char, i| 
    {
        result[i] = c_ushort(u8char);
    }
    result[string_literal.len] = 0;
    return result;
}

fn Win32GetWindowDimension(Window: HWND) win32_window_dimension
{
    var ClientRect: RECT = undefined;
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

fn HandleKey(VKCode: WPARAM, LParam: LPARAM) void
{
    const WasDown = LParam & (1 << 30) != 0;
    const IsDown = LParam & (1 << 31) == 0;
    if (IsDown == WasDown) {
        return;
    }
    switch(VKCode) {
        'W' => {},
        'A' => {},
        'S' => {},
        'D' => {},
        w32c.VK_UP => {},
        w32c.VK_LEFT => {},
        w32c.VK_DOWN => {},
        w32c.VK_RIGHT => {},
        w32c.VK_ESCAPE => {
            w32f.OutputDebugStringA(c"Escape Pressed!\n");
        },
        w32c.VK_SPACE => {},
        else => {}
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
            GlobalRunning = false;
        },
        w32c.WM_CLOSE => {
            // closed by user
            GlobalRunning = false;
        },
        w32c.WM_ACTIVATEAPP => {
            w32f.OutputDebugStringA(c"WM_ACTIVATEAPP\n");
        },
        w32c.WM_SYSKEYDOWN => {
            HandleKey(WParam, LParam);
        },
        w32c.WM_SYSKEYUP => {
            HandleKey(WParam, LParam);
        },
        w32c.WM_KEYDOWN => {
            HandleKey(WParam, LParam);
        },
        w32c.WM_KEYUP => {
            HandleKey(WParam, LParam);
        },
        w32c.WM_PAINT => {           
            var Paint: PAINTSTRUCT = undefined;

            var DeviceContext = w32f.BeginPaint(Window, &Paint);

            const Dimension = Win32GetWindowDimension(Window);
            Win32DisplayBufferInWindow(GlobalBackBuffer, 
                                       DeviceContext, 
                                       Dimension.Width,
                                       Dimension.Height);

            // Releases the DC as well.
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
    var Result: c_int = 0;
    const ClassNamePtr = (comptime w32str(&"HandmadeHeroWindowClass"))[0..].ptr;

    var WindowClass: WNDCLASSW = undefined;
    WindowClass.style = w32c.CS_HREDRAW | w32c.CS_VREDRAW | w32c.CS_OWNDC;
    WindowClass.lpfnWndProc = Win32MainWindowCallback;
    WindowClass.hInstance = Instance;
    WindowClass.lpszClassName = ClassNamePtr;

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
                null
            );

        if (Window != null) 
        {
            const DeviceContext = w32f.GetDC(Window);
            defer { const ignored = w32f.ReleaseDC(Window, DeviceContext); }

            GlobalRunning = true;
            var XOffset: u32 = 0;
            var YOffset: u32 = 0;
            while(GlobalRunning) 
            {


                // Process OS messages
                var Message: MSG = undefined;
                var MessageResult: BOOL = w32f.PeekMessageW(LPMSG(&Message), null, UINT(0), UINT(0), w32c.PM_REMOVE);
                while (MessageResult != 0)
                {
                    if (Message.message == w32c.WM_QUIT)
                    {
                        GlobalRunning = false;
                        Result = @intCast(c_int, Message.wParam);
                        MessageResult = 0;
                    } 
                    else
                    {
                        const ignored1 = w32f.TranslateMessage(&Message);
                        const ignored2 = w32f.DispatchMessageW(&Message);
                        MessageResult = w32f.PeekMessageW(LPMSG(&Message), null, UINT(0), UINT(0), w32c.PM_REMOVE);
                    }
                }


                // Poll controllers
                const num_controllers = 4;
                var ControllerIndex: u32 = 0;
                while(ControllerIndex < num_controllers) 
                {
                    var ControllerState: XINPUT_STATE = undefined;

                    const errorcode = XInputGetState(ControllerIndex, &ControllerState);
                    if(errorcode == w32c.ERROR_SUCCESS)
                    {
                        const Pad = ControllerState.Gamepad;
                        const Up            = (Pad.wButtons & XINPUT_GAMEPAD_DPAD_UP) != 0;
                        const Down          = (Pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN) != 0;
                        const Left          = (Pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT) != 0;
                        const Right         = (Pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0;
                        const Start         = (Pad.wButtons & XINPUT_GAMEPAD_START) != 0;
                        const Back          = (Pad.wButtons & XINPUT_GAMEPAD_BACK) != 0;
                        const LeftShoulder  = (Pad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0;
                        const RightShoulder = (Pad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0;
                        const AButton       = (Pad.wButtons & XINPUT_GAMEPAD_A) != 0;
                        const BButton       = (Pad.wButtons & XINPUT_GAMEPAD_B) != 0;
                        const XButton       = (Pad.wButtons & XINPUT_GAMEPAD_X) != 0;
                        const YButton       = (Pad.wButtons & XINPUT_GAMEPAD_Y) != 0;

                        const StickX = Pad.sThumbLX;
                        const StickY = Pad.sThumbLY;

                        if(AButton) 
                        {
                            YOffset = YOffset +% 2;
                        }
                    }
                    else
                    {
                        // controller not available
                    }
                    ControllerIndex += 1;
                }
                

                // Render
                RenderWeirdGradient(&GlobalBackBuffer, XOffset, YOffset);
                const Dimension = Win32GetWindowDimension(Window);
                Win32DisplayBufferInWindow(GlobalBackBuffer, 
                                           DeviceContext, 
                                           Dimension.Width,
                                           Dimension.Height);
                                           
                XOffset = XOffset +% 1;
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
        w32f.OutputDebugStringA(c"No atom\n");
    }
    return Result;
}