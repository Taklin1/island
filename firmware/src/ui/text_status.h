// Plain-text status screen (issue #158). Replaced by the mascot in #159.
#pragma once

#include <Arduino.h>

#include "receiver.h"

namespace ui {

/// Builds the screen once; afterwards only label texts change.
void textStatusBegin();

/// Replaces the status with a configuration problem (server not started).
void textStatusShowConfigProblem(const char* problem);

/// Refreshes the labels from the current state. Cheap to call often: a
/// label is only touched when its text changes, so nothing flickers.
void textStatusUpdate(const totem::SnapshotReceiver& receiver, uint32_t nowMs, const String& ip);

}  // namespace ui
