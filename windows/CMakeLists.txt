cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "lightweight_rich_editor")
set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

project(${PROJECT_NAME} LANGUAGES CXX)

add_library(${PLUGIN_NAME} SHARED
  "lightweight_rich_editor_plugin.cpp"
)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  COMPILE_FLAGS "/DLIGHTWEIGHT_RICH_EDITOR_PLUGIN_EXPORTS"
)

target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
