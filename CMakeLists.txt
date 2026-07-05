cmake_minimum_required(VERSION 3.20)

project(qVis)

set(CMAKE_CXX_STANDARD 20)

# Allow undefined symbols since kdb+ API (e.g. krr) is provided by the main executable q
if (APPLE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -undefined dynamic_lookup")
endif()

find_package(SDL3 REQUIRED)

add_library(qSDL SHARED qSDL.cpp)
target_link_libraries(qSDL PRIVATE SDL3::SDL3)
# To avoid the "lib" prefix for q shared libraries, we set the output name and prefix
set_target_properties(qSDL PROPERTIES PREFIX "" OUTPUT_NAME "qSDL" SUFFIX ".so")
