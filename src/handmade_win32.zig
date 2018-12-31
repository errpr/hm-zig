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
const math = std.math;
const assert = std.debug.assert;
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

fn Win32ClearSoundBuffer(SecondaryBufferSize: u32) void
{
    var Region1: ?*c_void = null;
    var Region1Size: DWORD = 0;
    var Region2: ?*c_void = null;
    var Region2Size: DWORD = 0;
    const dsBuf = GlobalSecondaryBuffer.lpVtbl orelse return;
    const hResult = dsBuf.Lock(GlobalSecondaryBuffer, 0, SecondaryBufferSize, 
                                &Region1, &Region1Size, 
                                &Region2, &Region2Size, 0);
    if (hResult == 0)
    {
        var ByteIndex: u32 = 0;
        var DestByte = @ptrCast([*]u8, Region1);
        while (ByteIndex < Region1Size)
        {
            DestByte.* = 0;
            DestByte += 1;
            ByteIndex +%= 1;
        }

        DestByte = @ptrCast([*]u8, Region2);
        ByteIndex = 0;
        while (ByteIndex < Region2Size)
        {
            DestByte.* = 0;
            DestByte += 1;
            ByteIndex +%= 1;
        }
        _ = dsBuf.Unlock(GlobalSecondaryBuffer, Region1, Region1Size, Region2, Region2Size);
    }
}
//NOTE Casey uses a struct for most of these values, I've deviated and just pass everything as individual parameters.
fn Win32FillSoundBuffer(ByteToLock: DWORD, BytesPerSample: DWORD, 
                        BytesToWrite: DWORD, GameSound: *game_output_sound_buffer,
                        RunningSampleIndex: *u32) void
{
    var Region1: ?*c_void = null;
    var Region1Size: DWORD = 0;
    var Region2: ?*c_void = null;
    var Region2Size: DWORD = 0;
    const dsBuf = GlobalSecondaryBuffer.lpVtbl orelse return;
    const hResult = dsBuf.Lock(GlobalSecondaryBuffer, ByteToLock, BytesToWrite, 
                                &Region1, &Region1Size, 
                                &Region2, &Region2Size, 0);
    if (hResult == 0)
    {
        //w32f.OutputDebugStringA(c"We are writing to the sound buffer\n");
        var SampleOut = @ptrCast([*]i16, @alignCast(2, Region1));
        var SampleIndex: u32 = 0;
        var GameIndex: u32 = 0;
        const Region1SampleCount = Region1Size / BytesPerSample;
        while (SampleIndex < Region1SampleCount)
        {
            SampleOut.* = GameSound.Samples[GameIndex];
            SampleOut += 1;
            GameIndex += 1;
            if (GameIndex >= GameSound.SampleCount * 2) { GameIndex = 0; }
            SampleOut.* = GameSound.Samples[GameIndex];
            SampleOut += 1;
            GameIndex += 1;
            if (GameIndex >= GameSound.SampleCount * 2) { GameIndex = 0; }
            SampleIndex += 1;
            RunningSampleIndex.* +%= 1;
        }
        SampleIndex = 0;
        SampleOut = @ptrCast([*]i16, @alignCast(2, Region2));
        const Region2SampleCount = Region2Size / BytesPerSample;
        while (SampleIndex < Region2SampleCount)
        { 
            SampleOut.* = GameSound.Samples[GameIndex];
            SampleOut += 1;
            GameIndex += 1;
            if (GameIndex >= GameSound.SampleCount * 2) { GameIndex = 0; }
            SampleOut.* = GameSound.Samples[GameIndex];
            SampleOut += 1;
            GameIndex += 1;
            if (GameIndex >= GameSound.SampleCount * 2) { GameIndex = 0; }
            SampleIndex += 1;
            RunningSampleIndex.* +%= 1;
        }
        _ = dsBuf.Unlock(GlobalSecondaryBuffer, Region1, Region1Size, Region2, Region2Size);
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

fn Win32ProcessXInputDigitalButton(OldState: game_button_state, EndedDown: bool) game_button_state
{
    var htc: u8 = 0;
    if (EndedDown == OldState.EndedDown)
    {
        htc = 1;
    }
    return game_button_state {
        .EndedDown = EndedDown,
        .HalfTransitionCount = htc,
    };
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
            
            var GameMemory: game_memory = undefined;
            GameMemory.IsInitialized = false;
            GameMemory.PermanentStorageSize = 64 * 1024 * 1024;
            GameMemory.TransientStorageSize = 2 * 1024 * 1024 * 1024;
            var TotalSize = GameMemory.PermanentStorageSize + GameMemory.TransientStorageSize;
            var mem = w32f.VirtualAlloc(null, TotalSize, w32c.MEM_RESERVE|w32c.MEM_COMMIT, w32c.PAGE_READWRITE) orelse return 2;
            GameMemory.PermanentStorage = @ptrCast([*]u8, mem);
            GameMemory.TransientStorage = GameMemory.PermanentStorage + GameMemory.PermanentStorageSize;
            
            defer { _ = w32f.VirtualFree(GameMemory.PermanentStorage, TotalSize, w32c.MEM_RELEASE); }

            var InputState: game_input = undefined;
            {
                var ControllerIndex: u32 = 0;
                while (ControllerIndex < InputState.Controllers.len) : (ControllerIndex += 1)
                {
                    InputState.Controllers[ControllerIndex] = game_controller_input {
                        .IsAnalog = true,
                        .StartX = 0,
                        .StartY = 0,
                        .MinX = 0,
                        .MinY = 0,
                        .MaxX = 0,
                        .MaxY = 0,
                        .EndX = 0,
                        .EndY = 0,
                        .Up = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .Down = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .Left = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .Right = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .LeftShoulder = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .RightShoulder = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .AButton = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .BButton = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .XButton = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                        .YButton = game_button_state { .HalfTransitionCount = 0, .EndedDown = false },
                    };
                }
            }

            // sound
            const SamplesPerSecond = 48000;
            const BytesPerSample = @sizeOf(i16) * 2;
            const SecondaryBufferSize = SamplesPerSecond * BytesPerSample;
            var RunningSampleIndex: u32 = 0;
            var LatencySampleCount: u32 = SamplesPerSecond / 15;

            var GameSampleMem = w32f.VirtualAlloc(null, SecondaryBufferSize, w32c.MEM_RESERVE|w32c.MEM_COMMIT, w32c.PAGE_READWRITE);
            var SoundBuffer: game_output_sound_buffer = undefined;
            SoundBuffer.SamplesPerSecond = SamplesPerSecond;
            SoundBuffer.tSine = 0;
            SoundBuffer.Samples = @ptrCast([*]i16, @alignCast(2, GameSampleMem));

            Win32InitDSound(Window, SecondaryBufferSize, SamplesPerSecond);
            Win32ClearSoundBuffer(SecondaryBufferSize);

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

                        var StartX: f32 = 0;
                        var StartY: f32 = 0;
                        var MaxX: f32 = 0;
                        var MaxY: f32 = 0;
                        var MinX: f32 = 0;
                        var MinY: f32 = 0;
                        var EndX: f32 = 0;
                        var EndY: f32 = 0;

                        var StickX: f32 = 0;
                        var StickY: f32 = 0;
                        if (Pad.sThumbLX < 0)
                        {
                            StickX = @intToFloat(f32, Pad.sThumbLX) / 32768.0;
                        }
                        else
                        {
                            StickX = @intToFloat(f32, Pad.sThumbLX) / 32767.0;
                        }

                        if (Pad.sThumbLY < 0)
                        {
                            StickY = @intToFloat(f32, Pad.sThumbLY) / 32768.0;
                        }
                        else
                        {
                            StickY = @intToFloat(f32, Pad.sThumbLY) / 32767.0;
                        }

                        StartX = InputState.Controllers[ControllerIndex].EndX;
                        StartY = InputState.Controllers[ControllerIndex].EndY;
                        var NewState = game_controller_input {
                            .IsAnalog = true,
                            .StartX = StartX,
                            .StartY = StartY,
                            .MinX = StickX,
                            .MinY = StickY,
                            .MaxX = StickX,
                            .MaxY = StickY,
                            .EndX = StickX,
                            .EndY = StickY,
                            .Up = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].Up, Up),
                            .Down = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].Down, Down),
                            .Left = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].Left, Left),
                            .Right = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].Right, Right),
                            .LeftShoulder = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].LeftShoulder, LeftShoulder),
                            .RightShoulder = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].RightShoulder, RightShoulder),
                            .AButton = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].AButton, AButton),
                            .BButton = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].BButton, BButton),
                            .XButton = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].XButton, XButton),
                            .YButton = Win32ProcessXInputDigitalButton(InputState.Controllers[ControllerIndex].YButton, YButton),
                        };
                        InputState.Controllers[ControllerIndex] = NewState;
                    }
                    else
                    {
                        // controller not available
                    }
                    ControllerIndex += 1;
                }

                var PlayCursor: DWORD = 0;
                var WriteCursor: DWORD = 0;
                var ByteToLock: DWORD = undefined;
                var TargetCursor: DWORD = undefined;
                var BytesToWrite: DWORD = undefined;
                var SoundIsValid = false;
                if (GlobalSecondaryBuffer.lpVtbl) |dsBuf|
                {
                    var hResult1 = dsBuf.GetCurrentPosition(GlobalSecondaryBuffer, &WriteCursor, &PlayCursor);
                    if (hResult1 == 0)
                    {
                        ByteToLock = (RunningSampleIndex * BytesPerSample) % SecondaryBufferSize;
                        TargetCursor = (PlayCursor + (LatencySampleCount * BytesPerSample)) % SecondaryBufferSize;

                        if (ByteToLock > TargetCursor)
                        {
                            BytesToWrite = SecondaryBufferSize - ByteToLock;
                            BytesToWrite += TargetCursor;
                        }
                        else
                        {
                            BytesToWrite = TargetCursor - ByteToLock;
                        }
                        SoundIsValid = true;
                    }
                }

                var BitmapBuffer: game_offscreen_buffer = undefined;
                BitmapBuffer.Memory = GlobalBackBuffer.Memory;
                BitmapBuffer.Width = GlobalBackBuffer.Width;
                BitmapBuffer.Height = GlobalBackBuffer.Height;
                BitmapBuffer.Pitch = GlobalBackBuffer.Pitch;

                SoundBuffer.SampleCount = BytesToWrite / BytesPerSample;

                handmade_main.UpdateAndRender(&BitmapBuffer, &SoundBuffer, &InputState, &GameMemory);
                
                if (SoundIsValid)
                {
                    
                    Win32FillSoundBuffer(ByteToLock, BytesPerSample, BytesToWrite, &SoundBuffer, &RunningSampleIndex);
                    
                }

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