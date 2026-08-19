#include "presence_state.h"
#include <cstring>

struct StateName { const char* name; PresenceState state; };
static constexpr StateName kStates[] = {
  {"AVAILABLE", PresenceState::AVAILABLE}, {"BUSY", PresenceState::BUSY},
  {"IN_CALL", PresenceState::IN_CALL}, {"IN_MEETING", PresenceState::IN_MEETING},
  {"DND", PresenceState::DND}, {"PRESENTING", PresenceState::PRESENTING},
  {"AWAY", PresenceState::AWAY}, {"OFFLINE", PresenceState::OFFLINE},
  {"UNKNOWN", PresenceState::UNKNOWN},
};

const char* presenceName(PresenceState state) {
  for (const auto& entry : kStates) if (entry.state == state) return entry.name;
  return "UNKNOWN";
}

bool parsePresence(const char* text, PresenceState& state) {
  for (const auto& entry : kStates) {
    if (strcmp(text, entry.name) == 0) { state = entry.state; return true; }
  }
  return false;
}
