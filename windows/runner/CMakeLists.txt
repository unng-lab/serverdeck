cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_library(${BINARY_NAME} SHARED
  "flutter_window.cpp"
  "host_main.cpp"
  "platform_channel.cpp"
  "update_runtime.cpp"
  "../../native/bootstrap/security.cpp"
  "../../native/bootstrap/instance.cpp"
  "../../native/bootstrap/mcp_pipe.cpp"
  "../../native/install/release_catalog.cpp"
  "../../native/install/github_releases.cpp"
  "../../native/install/installation.cpp"
  "../../native/install/maintenance_handoff.cpp"
  "../../native/install/install_executor.cpp"
  "../../native/install/install_registration.cpp"
  "../../native/install/setup_package.cpp"
    "../../native/install/update_service.cpp"
    "../../native/install/artifact_transfer.cpp"
    "../../native/install/pending_update.cpp"
  "../../native/install/pending_lifecycle.cpp"
  "../../native/install/build_identity.cpp"
  "../../native/install/startup_update.cpp"
  "../../native/install/uninstall.cpp"
  "../../native/install/uninstall_cache.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})
set_target_properties(${BINARY_NAME} PROPERTIES
  OUTPUT_NAME "serverdeck_host"
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

# Product identity comes from pubspec; Flutter synthesizes a +1 build suffix
# when none is declared. Do not expose that synthetic suffix as release identity.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../../pubspec.yaml" SERVERDECK_VERSION_LINE REGEX "^version: ")
string(REGEX REPLACE "^version: +" "" SERVERDECK_VERSION "${SERVERDECK_VERSION_LINE}")
if(NOT SERVERDECK_VERSION MATCHES "^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$")
  message(FATAL_ERROR "Product version must be stable major.minor.patch")
endif()
set(FLUTTER_VERSION "${SERVERDECK_VERSION}")
set(FLUTTER_VERSION_MAJOR "${CMAKE_MATCH_1}")
set(FLUTTER_VERSION_MINOR "${CMAKE_MATCH_2}")
set(FLUTTER_VERSION_PATCH "${CMAKE_MATCH_3}")
set(FLUTTER_VERSION_BUILD 0)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../../pubspec.yaml")

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE bcrypt advapi32 ole32 shell32 user32 crypt32 winhttp ws2_32 uuid shlwapi)
target_include_directories(${BINARY_NAME} PRIVATE "../../native/include")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
