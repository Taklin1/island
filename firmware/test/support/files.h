// Reads repository files from native tests (issue #158): the contract
// fixtures stay in `firmware/contract/`, never copied under `test/`.
#pragma once

#include <unity.h>

#include <cstdio>
#include <string>

namespace test_support {

/// `firmware/`, from the contract dir injected by platformio.ini, or else
/// from this header's own path (firmware/test/support/).
inline std::string firmwareDir() {
#ifdef TOTEM_CONTRACT_DIR
    return std::string(TOTEM_CONTRACT_DIR) + "/..";
#else
    const std::string header = __FILE__;
    return header.substr(0, header.find_last_of('/')) + "/../..";
#endif
}

/// The content of `relativePath` under `firmware/`; fails the test if absent.
inline std::string readFirmwareFile(const std::string& relativePath) {
    const std::string path = firmwareDir() + "/" + relativePath;
    FILE* file = std::fopen(path.c_str(), "rb");
    if (file == nullptr) {
        TEST_FAIL_MESSAGE(("missing file " + path).c_str());
        return {};
    }
    std::string content;
    char buffer[512];
    size_t read = 0;
    while ((read = std::fread(buffer, 1, sizeof buffer, file)) > 0) content.append(buffer, read);
    std::fclose(file);
    return content;
}

inline std::string readFixture(const char* name) {
    return readFirmwareFile(std::string("contract/") + name);
}

}  // namespace test_support
