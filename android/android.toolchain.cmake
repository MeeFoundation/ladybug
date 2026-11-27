# The NDK's own toolchain for arm64, API 24, with one addition: the OpenSSL
# built for Android (scripts/android-openssl.sh) among the roots CMake may
# search. The NDK's toolchain confines every search to its sysroot, and
# LadybugDB from 0.22 on requires OpenSSL 3.
#
# Named as the NDK's file is, so the cmake crate treats it as the NDK's.
set(ANDROID_ABI arm64-v8a CACHE STRING "")
set(ANDROID_PLATFORM android-24 CACHE STRING "")
include("$ENV{ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake")
list(APPEND CMAKE_FIND_ROOT_PATH "$ENV{OPENSSL_ROOT_DIR}")
# Named outright: a root alone still lets FindOpenSSL ask pkg-config, which
# answers with the build machine's own OpenSSL.
set(OPENSSL_USE_STATIC_LIBS TRUE)
set(OPENSSL_INCLUDE_DIR "$ENV{OPENSSL_ROOT_DIR}/include" CACHE PATH "" FORCE)
set(OPENSSL_SSL_LIBRARY "$ENV{OPENSSL_ROOT_DIR}/lib/libssl.a" CACHE FILEPATH "" FORCE)
set(OPENSSL_CRYPTO_LIBRARY "$ENV{OPENSSL_ROOT_DIR}/lib/libcrypto.a" CACHE FILEPATH "" FORCE)
# And pkg-config, which FindOpenSSL asks for a static build's link flags,
# reads the Android OpenSSL's .pc files, not the build machine's.
set(ENV{PKG_CONFIG_LIBDIR} "$ENV{OPENSSL_ROOT_DIR}/lib/pkgconfig")
set(ENV{PKG_CONFIG_PATH} "")
