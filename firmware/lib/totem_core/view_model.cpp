#include "view_model.h"

#include "totem_sprites.h"

namespace totem {

Animation animationFor(AggregateState state) {
    switch (state) {
        case AggregateState::Idle: return Animation::Sleeping;
        case AggregateState::Working: return Animation::Working;
        case AggregateState::Done: return Animation::Finished;
        case AggregateState::Waiting: return Animation::Question;
    }
    return Animation::Sleeping;
}

ViewModel makeViewModel(bool connected, const Snapshot* snapshot) {
    ViewModel view;
    // Déconnecté (CONTEXT.md): grey sleeping mascot, Halo off, nothing stale.
    if (!connected || snapshot == nullptr) return view;
    view.connected = true;
    view.grey = false;
    view.animation = animationFor(snapshot->state);
    view.counts = snapshot->counts;
    view.halo = haloFor(true, snapshot->state);
    return view;
}

ViewModel viewModelFor(const SnapshotReceiver& receiver, uint32_t nowMs) {
    const bool connected = receiver.isConnected(nowMs);
    return makeViewModel(connected, receiver.hasSnapshot() ? &receiver.snapshot() : nullptr);
}

namespace {

bool sameCounts(const Counts& a, const Counts& b) {
    return a.waiting == b.waiting && a.done == b.done && a.working == b.working &&
           a.idle == b.idle;
}

/// Frame of `animation`'s loop after `elapsedMs`, as an index into kFrames.
/// Integer maths only (the ESP32-C6 has no FPU): fps are in millihertz.
uint8_t frameAt(Animation animation, uint32_t elapsedMs) {
    const sprites::Loop& loop = sprites::kLoops[static_cast<uint8_t>(animation)];
    const uint64_t ticks = static_cast<uint64_t>(elapsedMs) * loop.fpsMilli / 1000000u;
    return static_cast<uint8_t>(loop.firstFrame + ticks % loop.frames);
}

}  // namespace

PageUpdate PagePresenter::step(const ViewModel& next, uint32_t nowMs) {
    PageUpdate update;
    if (!started_) {
        update = {true, true, true, true};
        animationStartMs_ = nowMs;
    } else {
        update.link = next.connected != view_.connected;
        update.counts = update.link || !sameCounts(next.counts, view_.counts);
        update.halo = next.halo != view_.halo;
        const bool newAnimation = next.animation != view_.animation;
        // Only a new animation restarts the loop, never a new Instantané.
        if (newAnimation) animationStartMs_ = nowMs;
        update.mascot = newAnimation || next.grey != view_.grey;
    }

    // Unsigned difference: correct across the millis() wrap.
    const uint8_t frame = frameAt(next.animation, nowMs - animationStartMs_);
    if (started_ && frame != frame_) update.mascot = true;

    frame_ = frame;
    view_ = next;
    started_ = true;
    return update;
}

}  // namespace totem
