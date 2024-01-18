#! /bin/bash
#
# Kernel compile script for OnePlus 9RT
# Copyright (C) 2023-2024 InFeRnO.

# Setup environment
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
clear='\033[0m'
KERNEL_PATH=$PWD
ARCH=arm64
DEFCONFIG=vendor/lahaina-qgki_defconfig
CLANG_PATH=$KERNEL_PATH/.clang/clang-r530567
export PATH=$CLANG_PATH/bin:$PATH
FULL_LTO=auto
KernelSU=false
BUILD_CC="LLVM=1 LLVM_IAS=1 LD=ld.lld AR=llvm-ar AS=llvm-as NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf OBJSIZE=llvm-objsize STRIP=llvm-strip"

clone_tools() {
    cd $KERNEL_PATH
    git clone https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 --depth=1 $KERNEL_PATH/.clang
    git clone https://gitlab.com/inferno0230/AnyKernel3 --depth=1 $KERNEL_PATH/AnyKernel3
}

setup_ksu() {
    cd $KERNEL_PATH
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
    grep -q "CONFIG_MODULES=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_MODULES=y" >> "arch/arm64/configs/$DEFCONFIG"
    grep -q "CONFIG_KPROBES=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_KPROBES=y" >> "arch/arm64/configs/$DEFCONFIG"
    grep -q "CONFIG_HAVE_KPROBES=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_HAVE_KPROBES=y" >> "arch/arm64/configs/$DEFCONFIG"
    grep -q "CONFIG_KPROBE_EVENTS=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_KPROBE_EVENTS=y" >> "arch/arm64/configs/$DEFCONFIG"
}

set_lto_config() {
    if [[ $(echo "$(awk '/MemTotal/ {print $2}' /proc/meminfo) > 16000000" | bc -l) -eq 1 ]]; then
        echo -e "${green}Total RAM is greater than 16GB${clear}"
        echo -e "${green}Continuing with FULL_LTO Build${clear}"
        FULL_LTO=true
    else
        echo -e "${yellow}Total RAM is less than 16GB${clear}"
        echo "${yellow}Disabling LTO${clear}"
        sed -i 's/CONFIG_LTO=y/CONFIG_LTO=n/' out/.config
        sed -i 's/CONFIG_LTO_CLANG=y/CONFIG_LTO_CLANG=n/' out/.config
        sed -i 's/CONFIG_THINLTO=y/CONFIG_THINLTO=n/' out/.config
        echo "CONFIG_LTO_NONE=y" >> out/.config
        FULL_LTO=false
    fi
}

ArchLinux() {
    # Check if yay is installed
    if ! command -v yay &> /dev/null
    then
        echo -e "${red}yay is not installed, please install it first!${clear}"
        exit
    else
        yay -S lineageos-devel aosp-devel zstd tar wget curl base-devel lib32-ncurses lib32-zlib lib32-readline --noconfirm
    fi
}

Fedora() {
    curl -LSs "https://raw.githubusercontent.com/akhilnarang/scripts/master/setup/fedora.sh" | bash -
}

Ubuntu() {
    curl -LSs "https://raw.githubusercontent.com/akhilnarang/scripts/master/setup/android_build_env.sh" | bash -
}

regenerate_defconfig() {
    cd $KERNEL_PATH
    make O=out ARCH=arm64 $BUILD_CC $DEFCONFIG savedefconfig
    cp out/.config arch/arm64/configs/vendor/lahaina-qgki_defconfig
    git add arch/arm64/configs/vendor/lahaina-qgki_defconfig && git commit -m "defconfig: Regenerate"
}

build_kernel() {
    cd $KERNEL_PATH
    make O=out ARCH=arm64 CC=clang $BUILD_CC $DEFCONFIG savedefconfig
    if [ "$FULL_LTO" == "auto" ]; then
        set_lto_config
    elif [ "$FULL_LTO" == "false" ]; then
        echo -e "${yellow}FULL_LTO is set to false, disabling LTO${clear}"
        sed -i 's/CONFIG_LTO=y/CONFIG_LTO=n/' out/.config
        sed -i 's/CONFIG_LTO_CLANG=y/CONFIG_LTO_CLANG=n/' out/.config
        sed -i 's/CONFIG_THINLTO=y/CONFIG_THINLTO=n/' out/.config
        echo "CONFIG_LTO_NONE=y" >> out/.config
    else
        echo -e "${green}FULL_LTO is set to true, leaving LTO configuration as is${clear}"
    fi
    # Begin compilation
    start=$(date +%s)
    make O=out  CC='ccache clang' CXX='ccache clang++' ARCH=arm64 -j`nproc` ${BUILD_CC} 2>&1 | tee error.log
    if [ -f $KERNEL_PATH/out/arch/arm64/boot/Image ]; then
        echo -e "${green}Kernel Compilation successful!, Zipping...${clear}"
        make_anykernel3_zip
    else
        echo -e "${red}Compilation failed!${clear}"
        echo -e "${red}Check error.log for more info!${clear}"
        exit
    fi
}

make_anykernel3_zip() {
    cd $KERNEL_PATH
    # Extract the kernel version from the Makefile
    zip_name="OP9RT-v5.4.$(grep "^SUBLEVEL =" Makefile | awk '{print $3}')-$(date +"%Y%m%d-%H%M").zip"
    cd $KERNEL_PATH/AnyKernel3
    cp $KERNEL_PATH/out/arch/arm64/boot/Image $KERNEL_PATH/AnyKernel3
    zip -r kernel.zip *
    mv kernel.zip $KERNEL_PATH/out
    ln -sf $KERNEL_PATH/out/kernel.zip $KERNEL_PATH/out/${zip_name}
    echo -e "${green}out: ${KERNEL_PATH}/out/${zip_name}${clear}"
    echo -e "${clear}"
    echo -e "${green}Completed in $(($(date +%s) - start)) seconds.${clear}"
    cd $KERNEL_PATH
    exit
}

distro_check(){ 
    if [ -f /etc/arch-release ]; then
    echo -e "${green}Arch Linux detected!${clear}"
    ArchLinux
elif [ -f /etc/fedora-release ]; then
    echo -e "${green}Fedora detected!${clear}"
    Fedora
elif [ -f /etc/lsb-release ]; then
    echo -e "${green}Debian based distro detected!${clear}"
    Ubuntu
else
    echo -e "${red}Unsupported OS or ARCH!${clear}"
    exit
fi
}

start=$(date +%s)
if [ -d $CLANG_PATH ]; then
    echo -e "${blue}Clang exists, Skipping !${clear}"
else
    echo -e "${red}Clang is missing, Cloning...${clear}"
    echo -e "${yellow}This will take a while...${clear}"
    clone_tools
    distro_check
fi

# Parse Args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --regenerate) # To regenerate defconfig
            REGENERATE_DEFCONFIG=true
            shift
            ;;
        --clean) # To clean build kernel
            CLEAN_BUILD=true
            shift
            ;;
        --ksu) # To Enable KernelSU Compilation
            KernelSU=true
            shift
            ;;
        --nolto) # To disable LTO manually
            FULL_LTO=false
            shift
            ;;
        *) # ¯_(ツ)_/¯
            echo "$1: ¯_(ツ)_/¯"
            exit 1
            ;;
    esac
done

if [ "$REGENERATE_DEFCONFIG" = true ]; then
    regenerate_defconfig
    echo -e "${green}Defconfig regenerated successfully!${clear}"
    exit
fi

if [ "$CLEAN_BUILD" = true ]; then
    rm -rf out/
fi
    

# Check if KernelSU is enabled
if [ "$KernelSU" = true ]; then
    echo -e "${red}KernelSU compilation is Enabled!${clear}"
    setup_ksu
    build_kernel
    make_anykernel3_zip
else
    echo -e "${green}KernelSU compilation is disabled!${clear}"
    build_kernel
    make_anykernel3_zip
fi
