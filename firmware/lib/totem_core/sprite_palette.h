// Palettes of the exported mascot (issue #159). The Déconnecté Totem shows the
// sleeping mascot in greys: a palette swap to luminance, indices unchanged.
// Pure logic, computed at compile time.
#pragma once

#include <array>
#include <cstdint>

#include "totem_sprites.h"

namespace totem {

/// The grey of the same luminance as `rgb` (0xRRGGBB), Rec. 601 luma rounded.
constexpr uint32_t greyOf(uint32_t rgb) {
    const uint32_t r = (rgb >> 16) & 0xFF;
    const uint32_t g = (rgb >> 8) & 0xFF;
    const uint32_t b = rgb & 0xFF;
    const uint32_t y = (299 * r + 587 * g + 114 * b + 500) / 1000;
    return (y << 16) | (y << 8) | y;
}

/// `sprites::kPalette` with every colour replaced by its grey; index 0 stays
/// the transparent slot.
constexpr std::array<uint32_t, sprites::kPaletteSize> greyPalette() {
    std::array<uint32_t, sprites::kPaletteSize> grey{};
    for (uint8_t i = 0; i < sprites::kPaletteSize; ++i) grey[i] = greyOf(sprites::kPalette[i]);
    return grey;
}

}  // namespace totem
