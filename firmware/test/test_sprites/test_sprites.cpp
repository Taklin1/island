// Sprite tests (issue #159): the exported frames/fps table mirrors the app's
// SpriteSheet.bot, and the Déconnecté mascot is a luminance grey of it.
#include <unity.h>

#include <cstdio>
#include <string>

#include "../support/files.h"
#include "sprite_palette.h"
#include "totem_sprites.h"
#include "view_model.h"

using totem::Animation;
namespace sprites = totem::sprites;

void setUp() {}
void tearDown() {}

namespace {

const sprites::Loop& loopOf(Animation animation) {
    return sprites::kLoops[static_cast<uint8_t>(animation)];
}

}  // namespace

void test_the_table_pins_frames_and_fps_of_each_animation() {
    // MUST mirror SpriteSheet.bot (Sources/IslandUI/Sprites.swift).
    TEST_ASSERT_EQUAL_UINT8(4, sprites::kLoopCount);
    TEST_ASSERT_EQUAL_UINT8(4, loopOf(Animation::Working).frames);
    TEST_ASSERT_EQUAL_UINT16(4000, loopOf(Animation::Working).fpsMilli);
    TEST_ASSERT_EQUAL_UINT8(2, loopOf(Animation::Sleeping).frames);
    TEST_ASSERT_EQUAL_UINT16(1500, loopOf(Animation::Sleeping).fpsMilli);
    TEST_ASSERT_EQUAL_UINT8(4, loopOf(Animation::Finished).frames);
    TEST_ASSERT_EQUAL_UINT16(3000, loopOf(Animation::Finished).fpsMilli);
    TEST_ASSERT_EQUAL_UINT8(3, loopOf(Animation::Question).frames);
    TEST_ASSERT_EQUAL_UINT16(2500, loopOf(Animation::Question).fpsMilli);
}

void test_the_table_still_matches_sprites_swift() {
    // Catches a Swift change that was not re-exported to the firmware.
    const std::string swift = test_support::readFirmwareFile("../Sources/IslandUI/Sprites.swift");
    const size_t bot = swift.find("static let bot = SpriteSheet(loops: [");
    TEST_ASSERT_TRUE_MESSAGE(bot != std::string::npos, "SpriteSheet.bot not found");
    const std::string block = swift.substr(bot, swift.find("])", bot) - bot);

    const struct {
        const char* name;
        Animation animation;
        const char* fps;
    } rows[] = {
        {"working", Animation::Working, "4"},
        {"sleeping", Animation::Sleeping, "1.5"},
        {"finished", Animation::Finished, "3"},
        {"question", Animation::Question, "2.5"},
    };
    for (const auto& row : rows) {
        char entry[80];
        std::snprintf(entry, sizeof entry, ".%s: Loop(frames: %u, fps: %s)", row.name,
                      static_cast<unsigned>(loopOf(row.animation).frames), row.fps);
        TEST_ASSERT_TRUE_MESSAGE(block.find(entry) != std::string::npos, entry);
    }
}

void test_loops_tile_the_exported_frames_in_sheet_order() {
    uint8_t next = 0;
    for (uint8_t i = 0; i < sprites::kLoopCount; ++i) {
        TEST_ASSERT_EQUAL_UINT8(next, sprites::kLoops[i].firstFrame);
        next += sprites::kLoops[i].frames;
    }
    TEST_ASSERT_EQUAL_UINT8(13, sprites::kFrameCount);  // error row not exported
    TEST_ASSERT_EQUAL_UINT8(next, sprites::kFrameCount);
}

void test_every_frame_is_a_drawable_16x16_grid_of_palette_indices() {
    TEST_ASSERT_EQUAL_UINT8(16, sprites::kFrameSize);
    for (uint8_t f = 0; f < sprites::kFrameCount; ++f) {
        int opaque = 0;
        for (int i = 0; i < sprites::kFrameSize * sprites::kFrameSize; ++i) {
            TEST_ASSERT_TRUE(sprites::kFrames[f][i] < sprites::kPaletteSize);
            if (sprites::kFrames[f][i] != 0) ++opaque;
        }
        TEST_ASSERT_TRUE(opaque > 0);
    }
}

void test_the_palette_carries_the_bot_colours() {
    const uint32_t expected[] = {0xaeb6c2, 0x7d8694, 0x0d1117, 0x57d47a,
                                 0xf5a136, 0x4cd964, 0x8b93a1};
    for (uint32_t rgb : expected) {
        bool found = false;
        for (uint8_t i = 1; i < sprites::kPaletteSize; ++i) found |= sprites::kPalette[i] == rgb;
        TEST_ASSERT_TRUE(found);
    }
}

void test_grey_is_the_luminance_of_the_colour() {
    // Rec. 601 luma, rounded: Y = 0.299 R + 0.587 G + 0.114 B.
    TEST_ASSERT_EQUAL_HEX32(0x000000, totem::greyOf(0x000000));
    TEST_ASSERT_EQUAL_HEX32(0xFFFFFF, totem::greyOf(0xFFFFFF));
    TEST_ASSERT_EQUAL_HEX32(0x4C4C4C, totem::greyOf(0xFF0000));
    TEST_ASSERT_EQUAL_HEX32(0x969696, totem::greyOf(0x00FF00));
    TEST_ASSERT_EQUAL_HEX32(0x1D1D1D, totem::greyOf(0x0000FF));
    TEST_ASSERT_EQUAL_HEX32(0xA4A4A4, totem::greyOf(0x57d47a));  // code green
    TEST_ASSERT_EQUAL_HEX32(0x8B8B8B, totem::greyOf(0x8b8b8b));  // already grey
}

void test_the_grey_palette_keeps_every_index_and_greys_every_colour() {
    const auto grey = totem::greyPalette();
    TEST_ASSERT_EQUAL_UINT32(sprites::kPaletteSize, grey.size());
    for (uint8_t i = 1; i < sprites::kPaletteSize; ++i) {
        TEST_ASSERT_EQUAL_HEX32(totem::greyOf(sprites::kPalette[i]), grey[i]);
        const uint32_t rgb = grey[i];
        TEST_ASSERT_EQUAL_UINT8((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF);
        TEST_ASSERT_EQUAL_UINT8((rgb >> 8) & 0xFF, rgb & 0xFF);
    }
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_the_table_pins_frames_and_fps_of_each_animation);
    RUN_TEST(test_the_table_still_matches_sprites_swift);
    RUN_TEST(test_loops_tile_the_exported_frames_in_sheet_order);
    RUN_TEST(test_every_frame_is_a_drawable_16x16_grid_of_palette_indices);
    RUN_TEST(test_the_palette_carries_the_bot_colours);
    RUN_TEST(test_grey_is_the_luminance_of_the_colour);
    RUN_TEST(test_the_grey_palette_keeps_every_index_and_greys_every_colour);
    return UNITY_END();
}
