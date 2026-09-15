// The Halo (issue #159, CONTEXT.md § Halo): the Totem's glowing outline,
// mirror of the Mac's Liseré. Pure logic.
#pragma once

#include <cstdint>

#include "snapshot.h"

namespace totem {

enum class HaloColor : uint8_t { Off, Orange, Green };

/// Orange while a Session waits, green while one has finished, off otherwise
/// and whenever the Totem is Déconnecté (never a stale Halo). Follows the
/// aggregated state the Mac sends, which already accounts for the
/// Acquittement — whatever the Mac's "Edge outline" setting.
HaloColor haloFor(bool connected, AggregateState state);

/// 0xRRGGBB of a lit Halo (0 when off). The Halo mirrors the Liseré, so it
/// takes the Liseré's colours — SwiftUI `Color.orange` / `Color.green` in
/// Sources/IslandGlow/GlowWindow.swift, dark appearance (#FF9F0A / #30D158) —
/// rather than the Sprites' tints (#f5a136 / #4cd964), which stay on the
/// mascot itself.
uint32_t haloRgb(HaloColor color);

/// Inner glow: nested bands from the screen edge inwards, each fainter than
/// the previous one (echoes the Liseré's 0.9 stroke over a 0.5 soft layer).
/// No full-screen shadow: its cache would not fit the SRAM.
constexpr uint8_t kHaloBandCount = 4;
constexpr uint8_t kHaloBandOpa[kHaloBandCount] = {230, 140, 80, 35};

/// Breathing (AMOLED burn-in care): the whole Halo's level slowly swings
/// between kHaloBreathMin and 255 on its own clock, independent of the
/// Instantanés. Period and depth are to be confirmed on the board. The
/// period is a power of two so it divides 2^32: no jump at the millis() wrap.
constexpr uint32_t kHaloBreathPeriodMs = 8192;
constexpr uint8_t kHaloBreathMin = 153;  // 60 %

/// The breathing level at `nowMs` (millis()), 255 = full glow; multiplies
/// every band's opacity. Eased (smoothstep) so the swing never reads as a
/// blink.
uint8_t haloBreathLevel(uint32_t nowMs);

}  // namespace totem
