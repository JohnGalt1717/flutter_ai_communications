cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "flutter_ai_communications_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

list(APPEND PLUGIN_SOURCES
  "camera_graph.cpp"
  "camera_graph.h"
  "screen_graph.cpp"
  "screen_graph.h"
  "wgc_capture.cpp"
  "wgc_capture.h"
  "video_processor.cpp"
  "video_processor.h"
  "flutter_ai_communications_windows_plugin.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  "include/flutter_ai_communications_windows/flutter_ai_communications_windows_plugin.h"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
target_link_libraries(${PLUGIN_NAME} PRIVATE mf mfplat mfreadwrite mfuuid ole32
  gdi32 user32 dwmapi d3d11 dxgi windowsapp version windowscodecs)

set(SELFIE_MODEL "${CMAKE_CURRENT_SOURCE_DIR}/models/selfie_segmentation.onnx")
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${SELFIE_MODEL}"
  "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/selfie_segmentation.onnx")

set(flutter_ai_communications_windows_bundled_libraries
  "${SELFIE_MODEL}"
  PARENT_SCOPE
)
