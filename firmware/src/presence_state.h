#pragma once

enum class PresenceState {
  AVAILABLE, BUSY, IN_CALL, IN_MEETING, DND, PRESENTING, AWAY, OFFLINE, UNKNOWN
};

const char* presenceName(PresenceState state);
bool parsePresence(const char* text, PresenceState& state);
