// FIXME: is this really necessary? especially the "assumes big-endian" part.
//  this stinks like something i wrote before fully straightening out color
//  terminology in my head. for now just keeping it around for the sake of
//  simplifying the refactor.
// TODO: pick a color format and rename appropriately
pub const Color = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const empty: Color = @bitCast(@as(u32, 0x00000000));
    pub const white: Color = @bitCast(@as(u32, 0xFFFFFFFF));

    // WARN: assumes big-endian
    pub fn fromInt(color: u32) Color {
        return @bitCast(@byteSwap(color));
    }
};
