// TODO
//
// Saved game locations
// Getting a handle to our own executable failed
// Asset loading path
// Threading (launch a thread)
// Raw input (support for multiple keyboards)
// Sleep/timeBeginPeriod
// ClipCursor() (for multimonitor support)
// Fullscreen support
// WM_SETCURSOR (control cursor visibility)
// QueryCancelAutoplay
// WM_ACTIVATEAPP
// Blit speed improvement
// Hardware acceleration (OpenGL or D3D or BOTH)
// GetKeyboardLayout (for i18n)

use @import("handmade_shared_types.zig");
const std = @import("std");
const math = @import("std").math;
use @import("lib/win32/win32_types.zig");
const w32f = @import("lib/win32/win32_functions.zig");
const w32c = @import("lib/win32/win32_constants.zig");
const handmade_main = @import("handmade.zig");

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
var GlobalSecondaryBuffer: LPDIRECTSOUNDBUFFER = undefined;

pub const FARPROC = *@OpaqueType();
extern "kernel32" stdcallcc fn GetProcAddress(hModule: HMODULE, lpProcName: LPCSTR) FARPROC;

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

const XInputGetStateType = stdcallcc fn (dwUserIndex: DWORD, pState: *XINPUT_STATE) DWORD;
const XInputSetStateType = stdcallcc fn (dwUserIndex: DWORD, pVibration: *XINPUT_VIBRATION) DWORD;
const XInputEnableType   = stdcallcc fn (enable: BOOL) void;
var XInputGetState: XInputGetStateType = undefined;
var XInputSetState: XInputSetStateType = undefined;
var XInputEnable: XInputEnableType = undefined;

fn Win32LoadXInput() void
{
    // NOTE - using 1_3 because it doesn't stall on exit.
    var XInputLibrary = w32f.LoadLibraryA(c"xinput1_3.dll");
    
    if (XInputLibrary == null)
    {
        XInputLibrary = w32f.LoadLibraryA(c"xinput1_4.dll");
    }


    if (XInputLibrary != null)
    {
        XInputGetState = @ptrCast(XInputGetStateType, GetProcAddress(XInputLibrary, c"XInputGetState"));
        XInputSetState = @ptrCast(XInputSetStateType, GetProcAddress(XInputLibrary, c"XInputSetState"));
        XInputEnable = @ptrCast(XInputEnableType, GetProcAddress(XInputLibrary, c"XInputEnable"));
    }
    else
    {
        w32f.OutputDebugStringA(c"Couldn\'t load xinput dll.\n");
    }
}

// Stuff for direct sound COM interface
const DSBCAPS = extern struct 
{
    dwSize: DWORD,
    dwFlags: DWORD,
    dwBufferBytes: DWORD,
    dwUnlockTransferRate: DWORD,
    dwPlayCpuOverhead: DWORD,
};
const LPDSBCAPS = *DSBCAPS;

const DSBUFFERDESC = extern struct 
{
    dwSize: DWORD,
    dwFlags: DWORD,
    dwBufferBytes: DWORD,
    dwReserved: DWORD,
    lpwfxFormat: LPWAVEFORMATEX,
};
const LPDSBUFFERDESC = *DSBUFFERDESC;
const LPCDSBUFFERDESC = *DSBUFFERDESC;

const IDirectSoundBufferVtbl = extern struct 
{
    QueryInterface:         extern fn(?*IDirectSoundBuffer, ?*const IID, ?*(?*c_void)) HRESULT,
    AddRef:                 extern fn(?*IDirectSoundBuffer) ULONG,
    Release:                extern fn(?*IDirectSoundBuffer) ULONG,
    GetCaps:                extern fn(?*IDirectSoundBuffer, pDSBufferCaps: LPDSBCAPS) HRESULT,
    GetCurrentPosition:     extern fn(?*IDirectSoundBuffer, pdwCurrentPlayCursor: LPDWORD, pdwCurrentWriteCursor: LPDWORD) HRESULT,
    GetFormat:              extern fn(?*IDirectSoundBuffer, pwfxFormat: LPWAVEFORMATEX, dwSizeAllocated: DWORD, pdwSizeWritten: LPDWORD) HRESULT,
    GetVolume:              extern fn(?*IDirectSoundBuffer, plVolume: LPLONG) HRESULT,
    GetPan:                 extern fn(?*IDirectSoundBuffer, plPan: LPLONG) HRESULT,
    GetFrequency:           extern fn(?*IDirectSoundBuffer, pdwFrequency: LPDWORD) HRESULT,
    GetStatus:              extern fn(?*IDirectSoundBuffer, pdwStatus: LPDWORD) HRESULT,
    Initialize:             extern fn(?*IDirectSoundBuffer, pDirectSound: *IDirectSound, pcDSBufferDesc: LPCDSBUFFERDESC) HRESULT,
    Lock:                   extern fn(?*IDirectSoundBuffer, dwOffset: DWORD, dwBytes: DWORD, 
                                        ppvAudioPtr1: *LPVOID, pdwAudioBytes1: LPDWORD, 
                                        ppvAudioPtr2: *LPVOID, pdwAudioBytes2: LPDWORD,
                                        dwFlags: DWORD) HRESULT,
    Play:                   extern fn(?*IDirectSoundBuffer, dwReserved1: DWORD, dwPriority: DWORD, dwFlags: DWORD) HRESULT,
    SetCurrentPosition:     extern fn(?*IDirectSoundBuffer, dwNewPosition: DWORD) HRESULT,
    SetFormat:              extern fn(?*IDirectSoundBuffer, pcfxFormat: LPCWAVEFORMATEX) HRESULT,
    SetVolume:              extern fn(?*IDirectSoundBuffer, lVolume: LONG) HRESULT,
    SetPan:                 extern fn(?*IDirectSoundBuffer, lPan: LONG) HRESULT,
    SetFrequency:           extern fn(?*IDirectSoundBuffer, dwFrequency: DWORD) HRESULT,
    Stop:                   extern fn(?*IDirectSoundBuffer) HRESULT,
    Unlock:                 extern fn(?*IDirectSoundBuffer, pvAudioPtr1: LPVOID, dwAudioBytes1: DWORD, pvAudioPtr2: LPVOID, dwAudioBytes2: DWORD) HRESULT,
    Restore:                extern fn(?*IDirectSoundBuffer) HRESULT,
};
const IDirectSoundBuffer = extern struct 
{
    lpVtbl: ?*IDirectSoundBufferVtbl,
};
const LPDIRECTSOUNDBUFFER = *IDirectSoundBuffer;
const LPLPDIRECTSOUNDBUFFER = *LPDIRECTSOUNDBUFFER;

const DSCAPS = extern struct 
{
    dwSize:                             DWORD,
    dwFlags:                            DWORD,
    dwMinSecondarySampleRate:           DWORD,
    dwMaxSecondarySampleRate:           DWORD,
    dwPrimaryBuffers:                   DWORD,
    dwMaxHwMixingAllBuffers:            DWORD,
    dwMaxHwMixingStaticBuffers:         DWORD,
    dwMaxHwMixingStreamingBuffers:      DWORD,
    dwFreeHwMixingAllBuffers:           DWORD,
    dwFreeHwMixingStaticBuffers:        DWORD,
    dwFreeHwMixingStreamingBuffers:     DWORD,
    dwMaxHw3DMixingAllBuffers:          DWORD,
    dwMaxHw3DMixingStaticBuffers:       DWORD,
    dwMaxHw3DMixingStreamingBuffers:    DWORD,
    dwFreeHw3DMixingAllBuffers:         DWORD,
    dwFreeHw3DMixingStaticBuffers:      DWORD,
    dwFreeHw3DMixingStreamingBuffers:   DWORD,
    dwTotalHwMemBytes:                  DWORD,
    dwFreeHwMemBytes:                   DWORD,
    dwMaxContigFreeHwMemBytes:          DWORD,
    dwUnlockTransferRateHwBuffers:      DWORD,
    dwPlayCpuOverheadSwBuffer:          DWORD,
    dwReserved1:                        DWORD,
    dwReserved2:                        DWORD,
};
const LPDSCAPS = *DSCAPS;
const IDirectSoundVtbl = extern struct 
{
    // IUnknown methods
    QueryInterface:         extern fn(?*IDirectSound, ?*const IID, ?*(?*c_void)) HRESULT,
    AddRef:                 extern fn(?*IDirectSound) ULONG,
    Release:                extern fn(?*IDirectSound) ULONG,

    // IDirectSound methods
    CreateSoundBuffer:      extern fn(?*IDirectSound,
                                       lpcDSBufferDesc: LPCDSBUFFERDESC,
                                       lplpDirectSoundBuffer: **IDirectSoundBuffer,
                                       pUnkOuter: ?*IUnknown) HRESULT,
    GetCaps:                extern fn(?*IDirectSound, lpDSCaps: LPDSCAPS) HRESULT,    
    DuplicateSoundBuffer:   extern fn(?*IDirectSound, lpDsbOriginal: *IDirectSoundBuffer, lplpDsbDuplicate: **IDirectSoundBuffer) HRESULT,
    SetCooperativeLevel:    extern fn(?*IDirectSound, hwnd: HWND, dwLevel: DWORD) HRESULT,    
    Compact:                extern fn(?*IDirectSound) HRESULT,
    GetSpeakerConfig:       extern fn(?*IDirectSound, pdwSpeakerConfig: LPDWORD) HRESULT,    
    SetSpeakerConfig:       extern fn(?*IDirectSound, dwSpeakerConfig: DWORD) HRESULT,
    Initialize:             extern fn(?*IDirectSound, lpGuid: LPGUID) HRESULT,
};
const IDirectSound = extern struct 
{
    lpVtbl: ?*IDirectSoundVtbl,
};
const LPDIRECTSOUND = *IDirectSound;

const DSSCL_PRIORITY = 0x00000002;
const DSBCAPS_PRIMARYBUFFER = 0x00000001;
const DSBPLAY_LOOPING = 0x00000001;
const WAVE_FORMAT_PCM = WORD(1);

const DirectSoundCreateType = stdcallcc fn (pcGuidDevice: LPCGUID, ppDS: *LPDIRECTSOUND, pUnkOuter: LPUNKNOWN) HRESULT;
var DirectSoundCreate: DirectSoundCreateType = undefined;
fn Win32InitDSound(Window: HWND, BufferSize: DWORD, SamplesPerSecond: DWORD) void
{
    var DSoundLibrary = w32f.LoadLibraryA(c"dsound.dll");
    if (DSoundLibrary != null)
    {
        // something about COM
        DirectSoundCreate = @ptrCast(DirectSoundCreateType, GetProcAddress(DSoundLibrary, c"DirectSoundCreate"));

        var DirectSound: LPDIRECTSOUND = undefined;
        const hResult = DirectSoundCreate(null, &DirectSound, null);
        if  (hResult == 0)
        {
            var WaveFormat = WAVEFORMATEX {
                .wFormatTag = WAVE_FORMAT_PCM,
                .nChannels = 2,
                .nSamplesPerSec = SamplesPerSecond,
                .nAvgBytesPerSec = undefined,
                .nBlockAlign = undefined,
                .wBitsPerSample = 16,
                .cbSize = 0,
            };
            WaveFormat.nBlockAlign = (WaveFormat.nChannels * WaveFormat.wBitsPerSample) / 8;
            WaveFormat.nAvgBytesPerSec = WaveFormat.nBlockAlign * WaveFormat.nSamplesPerSec;

            const ds = DirectSound.lpVtbl orelse return;
            const hResult2 = ds.SetCooperativeLevel(DirectSound, Window, DSSCL_PRIORITY);
            if(hResult2 == 0)
            {
                // Create Primary Buffer
                var BufferDescription = DSBUFFERDESC {
                        .dwSize = @sizeOf(DSBUFFERDESC),
                        .dwFlags = DSBCAPS_PRIMARYBUFFER,
                        .dwBufferBytes = 0,
                        .dwReserved = 0,
                        .lpwfxFormat = null,
                };
                var PrimaryBuffer: LPDIRECTSOUNDBUFFER = undefined;
                const hResult3 = ds.CreateSoundBuffer(DirectSound, &BufferDescription, &PrimaryBuffer, null);
                if(hResult3 == 0)
                {
                    const dsb = PrimaryBuffer.lpVtbl orelse return;

                    const hResult4 = dsb.SetFormat(PrimaryBuffer, &WaveFormat);
                    if(hResult4 == 0)
                    {

                    }
                    else
                    {
                        w32f.OutputDebugStringA(c"Failed to set format of primary buffer.\n");
                    }
                }
                else
                {
                    w32f.OutputDebugStringA(c"Failed to create primary sound buffer.\n");
                }

            }
            else
            {
                w32f.OutputDebugStringA(c"Failed to set cooperative level.\n");
                return;
            }

            // Create Secondary Buffer
            var BufferDescription = DSBUFFERDESC {
                .dwSize = @sizeOf(DSBUFFERDESC),
                .dwFlags = 0,
                .dwBufferBytes = BufferSize,
                .dwReserved = 0,
                .lpwfxFormat = &WaveFormat,
            };
            
            const hResult5 = ds.CreateSoundBuffer(DirectSound, &BufferDescription, &GlobalSecondaryBuffer, null);
            if(hResult5 == 0)
            {

            }
            else
            {
                w32f.OutputDebugStringA(c"Failed to create secondary sound buffer.\n");
            }
        }
        else
        {
            w32f.OutputDebugStringA(c"Failed to create direct sound.\n");
        }
    }
    else
    {
        w32f.OutputDebugStringA(c"Failed to load direct sound library.\n");
    }
}

fn Win32GetWindowDimension(Window: HWND) win32_window_dimension
{
    var ClientRect: RECT = undefined;
    _ = w32f.GetClientRect(Window, &ClientRect);
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
            var Blue = @intCast(u32, @truncate(u8, @intCast(u32, X) +% XOffset));
            var Green = @intCast(u32, @truncate(u8, @intCast(u32, Y) +% YOffset));

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
    Buffer.Memory = w32f.VirtualAlloc(null, BufferMemorySize, w32c.MEM_RESERVE|w32c.MEM_COMMIT, w32c.PAGE_READWRITE);
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

    if (result == 0) 
    {
        w32f.OutputDebugStringA(c"StretchDIBits returned 0\n");
    }
}

fn HandleKey(VKCode: WPARAM, LParam: LPARAM) void
{
    const WasDown = LParam & (1 << 30) != 0;
    const IsDown = LParam & (1 << 31) == 0;
    
    if (IsDown == WasDown) 
    {
        return;
    }

    switch (VKCode) 
    {
        'W' => {},
        'A' => {},
        'S' => {},
        'D' => {},
        'Q' => {},
        'E' => {},
        w32c.VK_UP => {},
        w32c.VK_LEFT => {},
        w32c.VK_DOWN => {},
        w32c.VK_RIGHT => {},
        w32c.VK_ESCAPE => {
            w32f.OutputDebugStringA(c"Escape Pressed!\n");
        },
        w32c.VK_SPACE => {},
        w32c.VK_F4 => {
            // check for alt+f4
            if (LParam & (1 << 29) != 0)
            {
                GlobalRunning = false;
            }
        },
        else => {}
    }
}

pub stdcallcc fn Win32MainWindowCallback(Window: HWND,
                                         Message: UINT,
                                         WParam: WPARAM,
                                         LParam: LPARAM) LRESULT
{
    var Result = LRESULT(0);
    switch (Message) {
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
            // gained or lost focus
            XInputEnable(@intCast(BOOL, WParam));
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
            _ = w32f.EndPaint(Window, &Paint);
        },
        else => {
            Result = w32f.DefWindowProcA(Window, Message, WParam, LParam);
        },
    }
    return Result;
}

//NOTE Casey uses a struct for most of these values, I've deviated and just pass everything as individual parameters.
fn Win32FillSoundBuffer(ByteToLock: DWORD,  BytesToWrite: DWORD,
                        ToneVolume: u32,    BytesPerSample: u32, 
                        WavePeriod: u32,    RunningSampleIndex: *u32, tSine: *f32) void
{
    var Region1: ?*c_void = null;
    var Region1Size: DWORD = 0;
    var Region2: ?*c_void = null;
    var Region2Size: DWORD = 0;
    const dsBuf = GlobalSecondaryBuffer.lpVtbl orelse return;
    const hResult2 = dsBuf.Lock(GlobalSecondaryBuffer, ByteToLock, BytesToWrite, 
                                &Region1, &Region1Size, 
                                &Region2, &Region2Size, 0);
    if (hResult2 == 0)
    {
        //w32f.OutputDebugStringA(c"We are writing to the sound buffer\n");
        var SampleOut = @ptrCast([*]i16, @alignCast(2, Region1));
        var SampleIndex: u32 = 0;
        const Region1SampleCount = Region1Size / BytesPerSample;
        while (SampleIndex < Region1SampleCount)
        {
            const SineValue: f32 = math.sin(tSine.*);
            const SampleValue = @floatToInt(i16, (SineValue * @intToFloat(f32, ToneVolume)));
            SampleOut.* = SampleValue;
            SampleOut += 1;
            SampleOut.* = SampleValue;
            SampleOut += 1;
            SampleIndex += 1;
            tSine.* += 2.0 * math.pi * 1.0 / @intToFloat(f32, WavePeriod);
            RunningSampleIndex.* +%= 1;
        }
        SampleIndex = 0;
        SampleOut = @ptrCast([*]i16, @alignCast(2, Region2));
        const Region2SampleCount = Region2Size / BytesPerSample;
        while (SampleIndex < Region2SampleCount)
        { 
            const SineValue: f32 = math.sin(tSine.*);
            const SampleValue = @floatToInt(i16, (SineValue * @intToFloat(f32, ToneVolume)));
            SampleOut.* = SampleValue;
            SampleOut += 1;
            SampleOut.* = SampleValue;
            SampleOut += 1;
            SampleIndex += 1;
            tSine.* += 2.0 * math.pi * 1.0 / @intToFloat(f32, WavePeriod);
            RunningSampleIndex.* +%= 1;
        }
        const hResult3 = dsBuf.Unlock(GlobalSecondaryBuffer, Region1, Region1Size, Region2, Region2Size);
        if (hResult3 != 0)
        {
            w32f.OutputDebugStringA(c"Couldn't unlock buffer?\n");
        }
    }
    else
    {
        // w32f.OutputDebugStringA(c"Couldn't lock buffer\n");
        // couldn't lock buffer?
    }
}

pub fn PlatformLoadFile(str: []const u8) void
{
    var i: i32 = 1;
    i +%= 1;
}

pub export fn WinMain(Instance: HINSTANCE, 
                      PrevInstance: HINSTANCE, 
                      CommandLine: LPSTR, 
                      ShowCode: c_int) c_int 
{
    var Result: c_int = 0;

    Win32LoadXInput();

    var WindowClass: WNDCLASSA = undefined;
    WindowClass.style = w32c.CS_HREDRAW | w32c.CS_VREDRAW | w32c.CS_OWNDC;
    WindowClass.lpfnWndProc = Win32MainWindowCallback;
    WindowClass.hInstance = Instance;
    WindowClass.lpszClassName = c"HandmadeHeroClass";

    Win32ResizeDIBSection(&GlobalBackBuffer, 1280, 720);

    var PerfCountFrequencyResult: LARGE_INTEGER = undefined;
    _ = w32f.QueryPerformanceFrequency(&PerfCountFrequencyResult); 
    const PerfCountFrequency: i64 = PerfCountFrequencyResult.QuadPart;
    const PerfCountFrequencyFloat = @intToFloat(f32, PerfCountFrequency);

    const atom = w32f.RegisterClassA(&WindowClass);
    if (atom != 0) 
    {
        const Window = 
            w32f.CreateWindowExA(
                DWORD(0), 
                c"HandmadeHeroClass",
                c"Handmade Hero",
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
        defer { _ = w32f.DestroyWindow(Window); }
        if (Window != null) 
        {
            const DeviceContext = w32f.GetDC(Window);
            defer { _ = w32f.ReleaseDC(Window, DeviceContext); }

            GlobalRunning = true;

            // graphics
            var XOffset: u32 = 0;
            var YOffset: u32 = 0;

            // sound
            const SamplesPerSecond = 48000;
            const ToneVolume = 3000;
            const BytesPerSample = @sizeOf(i16) * 2;
            const SecondaryBufferSize = SamplesPerSecond * BytesPerSample;
            var ToneHz: u32 = 256;
            var WavePeriod = SamplesPerSecond / ToneHz;
            var RunningSampleIndex: u32 = 0;
            var tSine: f32 = 0.0;
            var LatencySampleCount: u32 = SamplesPerSecond / 15;

            Win32InitDSound(Window, SecondaryBufferSize, SamplesPerSecond);
            Win32FillSoundBuffer(0,
                                 LatencySampleCount * BytesPerSample,
                                 ToneVolume, 
                                 BytesPerSample,
                                 WavePeriod,
                                 &RunningSampleIndex,
                                 &tSine);
            if (GlobalSecondaryBuffer.lpVtbl) |gsb|
            {
                _ = gsb.Play(GlobalSecondaryBuffer, 0, 0, DSBPLAY_LOOPING);
            }

            var LastCounter: LARGE_INTEGER = undefined;
            _ = w32f.QueryPerformanceCounter(&LastCounter);
            // not sure how to get rdtsc working
            //var LastCycleCount = __rdtsc();

            while (GlobalRunning) 
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
                        _ = w32f.TranslateMessage(&Message);
                        _ = w32f.DispatchMessageW(&Message);
                        MessageResult = w32f.PeekMessageW(LPMSG(&Message), null, UINT(0), UINT(0), w32c.PM_REMOVE);
                    }
                }


                // Poll controllers
                const num_controllers = 4;
                var ControllerIndex: u32 = 0;
                while (ControllerIndex < num_controllers) 
                {
                    var ControllerState: XINPUT_STATE = undefined;

                    const errorcode = XInputGetState(ControllerIndex, &ControllerState);
                    if (errorcode == w32c.ERROR_SUCCESS)
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

                        const StickX = @intCast(i32, Pad.sThumbLX);
                        const AbsStickX = if(StickX > 0) @intCast(u32, StickX) else @intCast(u32, -StickX);
                        if(StickX > 0)
                        {
                            XOffset +%= AbsStickX >> 12;
                        }
                        else
                        {
                            XOffset -%= AbsStickX >> 12;
                        }

                        const StickY = @intCast(i32, Pad.sThumbLY);
                        const AbsStickY = if(StickY > 0) @intCast(u32, StickY) else @intCast(u32, -StickY);
                        if(StickY > 0)
                        {
                            YOffset +%= AbsStickY >> 12;
                        }
                        else
                        {
                            YOffset -%= AbsStickY >> 12;
                        }
                        const NormalizedStickX: f32 = @intToFloat(f32, AbsStickX) / 30000.0;
                        ToneHz = 512 + @floatToInt(u32, NormalizedStickX * 256.0);
                    }
                    else
                    {
                        // controller not available
                    }
                    ControllerIndex += 1;
                }
                
                // Sound
                if (GlobalSecondaryBuffer.lpVtbl) |dsBuf|
                {
                    var PlayCursor: DWORD = 0;
                    var WriteCursor: DWORD = 0;
                    var hResult1 = dsBuf.GetCurrentPosition(GlobalSecondaryBuffer, &WriteCursor, &PlayCursor);
                    if (hResult1 == 0)
                    {
                        const ByteToLock = (RunningSampleIndex * BytesPerSample) % SecondaryBufferSize;
                        const TargetCursor = (PlayCursor + (LatencySampleCount * BytesPerSample)) % SecondaryBufferSize;
                        var BytesToWrite: DWORD = undefined;
                        if (ByteToLock > TargetCursor)
                        {
                            BytesToWrite = SecondaryBufferSize - ByteToLock;
                            BytesToWrite += TargetCursor;
                        }
                        else
                        {
                            BytesToWrite = TargetCursor - ByteToLock;
                        }
                        WavePeriod = SamplesPerSecond / ToneHz;
                        Win32FillSoundBuffer(ByteToLock,    BytesToWrite,
                                             ToneVolume,    BytesPerSample, 
                                             WavePeriod,    &RunningSampleIndex, &tSine);
                    }
                }

                // Render
                var Buffer: game_offscreen_buffer = undefined;
                Buffer.Memory = GlobalBackBuffer.Memory;
                Buffer.Width = GlobalBackBuffer.Width;
                Buffer.Height = GlobalBackBuffer.Height;
                Buffer.Pitch = GlobalBackBuffer.Pitch;

                handmade_main.UpdateAndRender(&Buffer, XOffset, YOffset);

                const Dimension = Win32GetWindowDimension(Window);
                Win32DisplayBufferInWindow(GlobalBackBuffer, 
                                           DeviceContext, 
                                           Dimension.Width,
                                           Dimension.Height);
                
                // Performance Timing
                var EndCounter: LARGE_INTEGER = undefined;
                _ = w32f.QueryPerformanceCounter(&EndCounter);
                const CounterElapsed = @intToFloat(f32, EndCounter.QuadPart - LastCounter.QuadPart);
                const MSPerFrame = (1000 * CounterElapsed) / PerfCountFrequencyFloat;
                const FPS = PerfCountFrequencyFloat / CounterElapsed;
                var StringBuffer: [256]u8 = undefined;
                _ = w32f.wsprintfA(&StringBuffer, c"Milliseconds/frame: %d | %dFPS\n", @floatToInt(i32, MSPerFrame), @floatToInt(i32, FPS));
                // _ = StringCbPrintfA(&StringBuffer, @sizeOf(u8) * 256, c"Milliseconds/frame: %f | %fFPS\n", MSPerFrame, FPS);
                w32f.OutputDebugStringA(&StringBuffer);
                LastCounter = EndCounter;
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