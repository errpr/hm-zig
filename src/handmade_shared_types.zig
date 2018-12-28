pub const game_offscreen_buffer = struct 
{
    Memory: ?*c_void,
    Width: c_int,
    Height: c_int,
    Pitch: usize,
};