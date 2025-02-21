#!/bin/bash

set -e # bail on failure
set -x # echo commands


# brew install glslang

LLVM_VERSION=20.1.0-rc2
MESA_VERSION=25.0.0

MESA_ARCH=arm64
TARGET_ARCH=arm64
LLVM_TARGETS_TO_BUILD=AArch64
TARGET_ARCH_NAME=aarch64

wget -c -nv https://archive.mesa3d.org/mesa-${MESA_VERSION}.tar.xz
echo "96a53501fd59679654273258c6c6a1055a20e352ee1429f0b123516c7190e5b0 mesa-${MESA_VERSION}.tar.xz" | sha256sum -c
tar -xJf mesa-25.0.0.tar.xz

wget -c -nv https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-${LLVM_VERSION}.src.tar.xz
wget -c -nv https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/cmake-${LLVM_VERSION}.src.tar.xz
tar -xJf llvm-${LLVM_VERSION}.src.tar.xz
tar -xJf cmake-${LLVM_VERSION}.src.tar.xz

(
    rm -rf llvm.src cmake
    mv llvm-${LLVM_VERSION}.src llvm.src
    mv cmake-${LLVM_VERSION}.src cmake
    cmake \
        -G Ninja \
        -S llvm.src \
        -B llvm.build-native \
        -D CMAKE_INSTALL_PREFIX="`pwd`/llvm-native" \
        -D CMAKE_BUILD_TYPE=Release \
        -D BUILD_SHARED_LIBS=OFF \
        -D LLVM_TARGETS_TO_BUILD=${LLVM_TARGETS_TO_BUILD} \
        -D LLVM_ENABLE_BACKTRACES=OFF \
        -D LLVM_ENABLE_UNWIND_TABLES=OFF \
        -D LLVM_ENABLE_CRASH_OVERRIDES=OFF \
        -D LLVM_ENABLE_LIBXML2=OFF \
        -D LLVM_ENABLE_LIBEDIT=OFF \
        -D LLVM_ENABLE_LIBPFM=OFF \
        -D LLVM_ENABLE_ZLIB=OFF \
        -D LLVM_ENABLE_Z3_SOLVER=OFF \
        -D LLVM_ENABLE_WARNINGS=OFF \
        -D LLVM_ENABLE_PEDANTIC=OFF \
        -D LLVM_ENABLE_WERROR=OFF \
        -D LLVM_ENABLE_ASSERTIONS=OFF \
        -D LLVM_BUILD_LLVM_DYLIB=ON \
        -D LLVM_ENABLE_RTTI=ON \
        -D LLVM_BUILD_LLVM_C_DYLIB=OFF \
        -D LLVM_BUILD_UTILS=OFF \
        -D LLVM_BUILD_TESTS=OFF \
        -D LLVM_BUILD_DOCS=OFF \
        -D LLVM_BUILD_EXAMPLES=OFF \
        -D LLVM_BUILD_BENCHMARKS=OFF \
        -D LLVM_INCLUDE_UTILS=OFF \
        -D LLVM_INCLUDE_TESTS=OFF \
        -D LLVM_INCLUDE_DOCS=OFF \
        -D LLVM_INCLUDE_EXAMPLES=OFF \
        -D LLVM_INCLUDE_BENCHMARKS=OFF \
        -D LLVM_ENABLE_BINDINGS=OFF \
        -D LLVM_OPTIMIZED_TABLEGEN=ON \
        -D LLVM_ENABLE_PLUGINS=OFF \
        -D LLVM_ENABLE_IDE=OFF
    ninja -C llvm.build-native llvm-tblgen llvm-config
    ninja -C llvm.build-native install-llvm-config
    ninja -C llvm.build-native llvm-headers llvm-libraries
    ninja -C llvm.build-native install-llvm-headers install-llvm-libraries
    #ninja -C llvm.build-${MESA_ARCH} llvm-headers llvm-libraries
    #ninja -C llvm.build-${MESA_ARCH} install-llvm-headers install-llvm-libraries
)

(
    python3 -m venv builder-venv
    source builder-venv/bin/activate && python3 -V
    pip install --upgrade pip
    pip install mako packaging setuptools pyyaml

    rm -rf mesa.src
    mv mesa-${MESA_VERSION} mesa.src
    mkdir -p mesa.src/subprojects/llvm && cp meson.llvm.build mesa.src/subprojects/llvm/meson.build

    meson setup \
          mesa.build-${MESA_ARCH} \
          mesa.src \
          --prefix="`pwd`/mesa-llvmpipe-${MESA_ARCH}" \
          --default-library=static \
          -Dbuildtype=release \
          -Db_ndebug=true \
          -Dllvm=enabled \
          -Dplatforms=macos \
          -Dosmesa=true \
          -Dglx=disabled \
          -Dgallium-drivers=swrast \
          -Dvulkan-drivers=swrast
    ninja -C mesa.build-${MESA_ARCH} install
    #python mesa.src/src/vulkan/util/vk_icd_gen.py --api-version 1.4 --xml mesa.src/src/vulkan/registry/vk.xml --lib-path vulkan_lvp.dylib --out mesa-llvmpipe-${MESA_ARCH}/bin/lvp_icd.${TARGET_ARCH_NAME}.json
    otool -L mesa-llvmpipe-${MESA_ARCH}/lib/libOSMesa*dylib
    otool -L mesa-llvmpipe-${MESA_ARCH}/lib/libvulkan_lvp.dylib
)

if [ "${GITHUB_WORKFLOW}" != "" ]; then
    (
        mkdir archive-osmesa
        cd archive-osmesa
        cp ../mesa-llvmpipe-${MESA_ARCH}/lib/libOSMesa*dylib .
        cp ../mesa-llvmpipe-${MESA_ARCH}/include/GL/osmesa.h .
        zip -r9v ../mesa-osmesa-${MESA_ARCH}-${MESA_VERSION}.zip *
    )
    (
        mkdir archive-lavapipe
        cd archive-lavapipe
        cp ../mesa-llvmpipe-${MESA_ARCH}/lib/libvulkan_lvp.dylib .
        cp ../mesa-llvmpipe-${MESA_ARCH}/share/vulkan/icd.d/lvp_icd.aarch64.json .
        zip -r9v ../mesa-lavapipe-${MESA_ARCH}-${MESA_VERSION}.zip * 
    )

    echo LLVM_VERSION=${LLVM_VERSION}>>${GITHUB_OUTPUT}
    echo MESA_VERSION=${MESA_VERSION}>>${GITHUB_OUTPUT}
fi
