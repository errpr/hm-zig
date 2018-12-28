use @import("handmade_shared_types.zig");

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

pub fn UpdateAndRender(BitmapBuffer: *game_offscreen_buffer, XOffset: u32, YOffset: u32) void 
{
    RenderWeirdGradient(BitmapBuffer, XOffset, YOffset);
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