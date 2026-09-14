cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "flutter_ai_communications_linux")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.10...3.24)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

list(APPEND PLUGIN_SOURCES
  "camera_graph.cc"
  "camera_graph.h"
  "screen_graph.cc"
  "screen_graph.h"
  "video_processor.cc"
  "video_processor.h"
  "flutter_ai_communications_linux_plugin.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)
pkg_check_modules(GDKPIXBUF REQUIRED IMPORTED_TARGET gdk-pixbuf-2.0)
pkg_check_modules(PIPEWIRE libpipewire-0.3)
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::X11)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GDKPIXBUF)
target_link_libraries(${PLUGIN_NAME} PRIVATE Threads::Threads)
target_link_libraries(${PLUGIN_NAME} PRIVATE ${CMAKE_DL_LIBS})
if(PIPEWIRE_FOUND)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE FAC_HAS_PIPEWIRE=1)
  target_include_directories(${PLUGIN_NAME} PRIVATE ${PIPEWIRE_INCLUDE_DIRS})
  target_link_libraries(${PLUGIN_NAME} PRIVATE ${PIPEWIRE_LIBRARIES})
  pkg_check_modules(EGL egl)
  pkg_check_modules(GLES2 glesv2)
  if(EGL_FOUND AND GLES2_FOUND)
    target_compile_definitions(${PLUGIN_NAME} PRIVATE FAC_HAS_EGL_DMABUF=1)
    target_include_directories(${PLUGIN_NAME} PRIVATE ${EGL_INCLUDE_DIRS}
                             ${GLES2_INCLUDE_DIRS} /usr/include/drm)
    target_link_libraries(${PLUGIN_NAME} PRIVATE ${EGL_LIBRARIES}
                          ${GLES2_LIBRARIES})
  endif()
endif()

find_library(ONNXRUNTIME_LIB NAMES onnxruntime)
if(NOT ONNXRUNTIME_LIB)
  file(GLOB _ort_so "/usr/lib/*/libonnxruntime.so*")
  if(_ort_so)
    list(GET _ort_so 0 ONNXRUNTIME_LIB)
  endif()
endif()
# Ubuntu/Debian libonnxruntime dynamically links libonnx.so. Both register
# ONNX operator schemas at load, which prints:
#   Schema error: ... already registered from file ./onnx/defs/...
# Official ORT builds static-link onnx with ONNX_DISABLE_STATIC_REGISTRATION.
if(ONNXRUNTIME_LIB)
  execute_process(
    COMMAND ldd "${ONNXRUNTIME_LIB}"
    OUTPUT_VARIABLE _ort_ldd
    ERROR_QUIET)
  if(_ort_ldd MATCHES "libonnx\\.so")
    message(STATUS
      "Skipping ${ONNXRUNTIME_LIB}: links libonnx.so (duplicate schema registration)")
    set(ONNXRUNTIME_LIB "")
  endif()
endif()
if(ONNXRUNTIME_LIB)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE FAC_HAS_ONNXRUNTIME=1)
  target_include_directories(${PLUGIN_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/onnxruntime")
  target_link_libraries(${PLUGIN_NAME} PRIVATE ${ONNXRUNTIME_LIB})
endif()

set(SELFIE_MODEL "${CMAKE_CURRENT_SOURCE_DIR}/models/selfie_segmentation.onnx")
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${SELFIE_MODEL}"
  "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/selfie_segmentation.onnx")

set(flutter_ai_communications_linux_bundled_libraries
  "${SELFIE_MODEL}"
  PARENT_SCOPE
)
