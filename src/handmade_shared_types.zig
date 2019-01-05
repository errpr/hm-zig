pub const platform_callbacks = struct 
{
    DEBUGReadEntireFile: fn ([*]const u8) debug_read_file_result,
    DEBUGFreeFileMemory: fn ([*]u8) void,
    DEBUGWriteEntireFile: fn ([*]const u8, u64, [*]u8) bool,
};

pub const debug_read_file_result = struct
{
    ContentsSize: u32,
    Contents: [*]u8,
};

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
    tSine: f32,
};

pub const game_clocks = struct 
{
    SecondsElapsed: f32,
};

pub const game_state = struct
{
    ToneHz: u32,
    XOffset: u32,
    YOffset: u32,
};

pub const game_memory = struct
{
    IsInitialized: bool,
    PermanentStorageSize: u64,
    PermanentStorage: [*]u8,
    TransientStorageSize: u64,
    TransientStorage: [*]u8,
};

pub const game_input = struct
{
    Controllers: [5]game_controller_input,
};

pub const game_button_state = struct 
{
    HalfTransitionCount: u8,
    EndedDown: bool,
};

pub const game_controller_input = struct
{
    IsConnected:    bool,
    IsAnalog:       bool,
    StickAverageX:  f32,
    StickAverageY:  f32,

    MoveUp:             game_button_state,
    MoveDown:           game_button_state,
    MoveLeft:           game_button_state,
    MoveRight:          game_button_state,
    LeftShoulder:       game_button_state,
    RightShoulder:      game_button_state,
    ActionUp:           game_button_state,
    ActionDown:         game_button_state,
    ActionLeft:         game_button_state,
    ActionRight:        game_button_state,
    Start:              game_button_state,
    Back:               game_button_state,
};