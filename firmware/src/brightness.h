// Totem brightness (issue #160): cyclic levels (lib/totem_core/
// brightness_levels.h) on the CO5300, persisted in NVS across reboots.
#pragma once

namespace brightness {

/// Reads the stored level (default when none) and applies it.
void begin();

/// Steps to the next level (a long press), applies and stores it.
void step();

}  // namespace brightness
