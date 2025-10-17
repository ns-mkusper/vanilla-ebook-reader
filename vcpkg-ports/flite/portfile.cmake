vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO festvox/flite
    REF v2.2
    SHA512 1ca2f4145651490ef8405fdb830a3b42e885020a7603d965f6a5581b01bed41047d396b38c2ceab138fc0b28d28078db17acd2b5a84c6444cb99d65c581afa72
)

if(NOT VCPKG_TARGET_IS_WINDOWS)
    message(FATAL_ERROR "flite port currently supports only Windows targets")
endif()

vcpkg_replace_string(
    "${SOURCE_PATH}/fliteDll.vcxproj"
    "v140_xp"
    "$(VCPKG_PLATFORM_TOOLSET)"
)

# Compile the static library by running the upstream build script.
vcpkg_execute_required_process(
    COMMAND ${CMAKE_COMMAND} -E chdir ${SOURCE_PATH} nmake /f makefile.mak config=Release
    WORKING_DIRECTORY ${SOURCE_PATH}
    LOGNAME build-flite-release
)

vcpkg_execute_required_process(
    COMMAND ${CMAKE_COMMAND} -E chdir ${SOURCE_PATH} nmake /f makefile.mak config=Debug
    WORKING_DIRECTORY ${SOURCE_PATH}
    LOGNAME build-flite-debug
)

file(GLOB FLITE_HEADERS "${SOURCE_PATH}/include/*.h")
file(INSTALL ${FLITE_HEADERS} DESTINATION "${CURRENT_PACKAGES_DIR}/include")

file(INSTALL "${SOURCE_PATH}/main/Release/flite.lib" DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
file(INSTALL "${SOURCE_PATH}/main/Debug/flite.lib" DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib")

foreach(CONFIG debug release)
    file(GLOB LIBS "${CURRENT_PACKAGES_DIR}/${CONFIG}/lib/fliteDll*.lib")
    foreach(LIB ${LIBS})
        get_filename_component(LIB_DIR "${LIB}" DIRECTORY)
        file(RENAME "${LIB}" "${LIB_DIR}/flite.lib")
    endforeach()
endforeach()

file(INSTALL
    "${SOURCE_PATH}/COPYING"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/flite"
    RENAME copyright
)
