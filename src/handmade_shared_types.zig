pub const game_offscreen_buffer = struct 
{
    Memory: ?*c_void,
    Width: c_int,
    Height: c_int,
    Pitch: usize,
};

pub const game_output_sound_buffer = struct
{
    Samples: [*]i16,
    SamplesPerSecond: u32,
    SampleCount: u32,
};