use @import("handmade_shared_types.zig");

const math = @import("std").math;

// pub const Game = struct 
// {
//     // functions provided to the game from the platform
    
//     PlatformLoadFile: fn ([]const u8) void,

//     // functions provided to the platform from the game

//     // should eventually take timing, controller input, bitmap buffer, sound buffer
//     pub fn UpdateAndRender(self: Game, BitmapBuffer: *game_offscreen_buffer, XOffset: u32, YOffset: u32) void 
//     {
//         RenderWeirdGradient(BitmapBuffer, XOffset, YOffset);
//     }
// };


pub fn UpdateAndRender(BitmapBuffer: *game_offscreen_buffer, 
                       SoundBuffer: *game_output_sound_buffer,
                       Input: *game_input,
                       GameState: *game_state) void 
{
    // input processing
    var Input0 = Input.Controllers[0];
    
    if (Input0.IsAnalog)
    {
        const StickX = Input0.EndX;
        if(StickX > 0)
        {
            GameState.XOffset +%= @floatToInt(u32, StickX * 10);
            const ToneValue = 512 + @floatToInt(i32, StickX * 256.0);
            if (ToneValue < 1)
            {
                GameState.ToneHz = 1;
            }
            else
            {
                GameState.ToneHz = @intCast(u32, ToneValue);
            }
        }
        else if(StickX < 0)
        {
            GameState.XOffset -%= @floatToInt(u32, -StickX * 10);
            const ToneValue = 512 - @floatToInt(i32, -StickX * 256.0);
            if (ToneValue < 1)
            {
                GameState.ToneHz = 1;
            }
            else
            {
                GameState.ToneHz = @intCast(u32, ToneValue);
            }
        }
        else
        {
            GameState.ToneHz = 512;
        }

        const StickY = Input0.EndY;
        if(StickY > 0)
        {
            GameState.YOffset +%= @floatToInt(u32, StickY * 10.0);
        }
        else
        {
            GameState.YOffset -%= @floatToInt(u32, -StickY * 10.0);
        }
    }
    else
    {
        // digital only or maybe keyboard
    }
    

    // sound
    OutputSound(SoundBuffer, GameState.ToneHz);
    
    // graphics
    RenderWeirdGradient(BitmapBuffer, GameState.XOffset, GameState.YOffset);
}

pub fn OutputSound(SoundBuffer: *game_output_sound_buffer, ToneHz: u32) void
{
    var SampleIndex: u32 = 0;
    const ToneVolume: f32 = 3000;
    const WavePeriod = @intToFloat(f32, SoundBuffer.SamplesPerSecond) / @intToFloat(f32, ToneHz);
    while (SampleIndex < SoundBuffer.SampleCount * 2)
    {
        const SineValue: f32 = math.sin(SoundBuffer.tSine);
        const SampleValue = @floatToInt(i16, SineValue * ToneVolume);
        SoundBuffer.Samples[SampleIndex] = SampleValue;
        SampleIndex += 1;
        SoundBuffer.Samples[SampleIndex] = SampleValue;
        SampleIndex += 1;
        SoundBuffer.tSine += 2.0 * math.pi * (1.0 / WavePeriod);
    }
}

fn RenderWeirdGradient(Buffer: *game_offscreen_buffer, XOffset: u32, YOffset: u32) void
{
    var Row = @ptrCast([*]u8, Buffer.Memory);
    var Y: i32 = 0;
    while (Y < Buffer.Height) 
    {
        var X: i32 = 0;
        var Pixel = @ptrCast([*]u32, @alignCast(4, Row));
        
        while (X < Buffer.Width)
        {
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