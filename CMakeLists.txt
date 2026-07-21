cmake_minimum_required(VERSION 3.28)
project(sms2 VERSION 0.1.0)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(ECMFindQmlModule)

ecm_find_qmlmodule(org.kde.kirigami REQUIRED)
find_package(KF6 REQUIRED COMPONENTS QQC2DesktopStyle)

set(CARGO_PROFILE debug)
set(CARGO_OPTIONS)
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    set(CARGO_PROFILE release)
    set(CARGO_OPTIONS --release)
endif()

add_custom_target(sms2 ALL
    COMMAND cargo build --target-dir ${CMAKE_CURRENT_BINARY_DIR} ${CARGO_OPTIONS}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/${CARGO_PROFILE}/sms2
)

install(PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/${CARGO_PROFILE}/sms2 DESTINATION ${KDE_INSTALL_BINDIR})
install(FILES org.kde.sms2.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES org.kde.sms2.metainfo.xml DESTINATION ${KDE_INSTALL_METAINFODIR})
