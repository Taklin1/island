#include "auth.h"

#include <cstring>

namespace totem {

bool isAuthorized(const char* configured, const char* presented) {
    if (configured == nullptr || presented == nullptr || configured[0] == '\0') return false;
    const size_t configuredLength = std::strlen(configured);
    if (std::strlen(presented) != configuredLength) return false;
    // Compare every byte so the timing does not reveal the matching prefix.
    unsigned char difference = 0;
    for (size_t i = 0; i < configuredLength; ++i) {
        difference |= static_cast<unsigned char>(configured[i] ^ presented[i]);
    }
    return difference == 0;
}

}  // namespace totem
