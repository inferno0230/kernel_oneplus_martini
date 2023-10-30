#! /bin/bash

# Setup environment
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
clear='\033[0m'
KERNEL_PATH=$PWD
ARCH=arm64
DEFCONFIG=vendor/lahaina-qgki_defconfig
CLANG_PATH=$HOME/tools/clang-r498229b
export PATH=$CLANG_PATH/bin:$PATH
KernelSU=false # Enable if you want KernelSU
BUILD_CC="LLVM=1 LLVM_IAS=1 CC=clang LD=ld.lld AR=llvm-ar AS=llvm-as NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf OBJSIZE=llvm-objsize STRIP=llvm-strip"

clone_tools() {
    cd $KERNEL_PATH
    git clone https://gitlab.com/inferno0230/clang-r498229b --depth=1 ~/tools/clang-r498229b
    git clone https://gitlab.com/inferno0230/AnyKernel3 --depth=1 $KERNEL_PATH/AnyKernel3
}

setup_ksu() {
    cd $KERNEL_PATH
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
    grep -q "CONFIG_MODULES=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_MODULES=y" >> "arch/arm64/configs/$DEFCONFIG"
    grep -q "CONFIG_KPROBES=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_KPROBES=y" >> "arch/arm64/configs/$DEFCONFIG"
    grep -q "CONFIG_HAVE_KPROBES=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_HAVE_KPROBES=y" >> "arch/arm64/configs/$DEFCONFIG"
    grep -q "CONFIG_KPROBE_EVENTS=y" "arch/arm64/configs/$DEFCONFIG" || echo "CONFIG_KPROBE_EVENTS=y" >> "arch/arm64/configs/$DEFCONFIG"
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

build_kernel() {
    cd $KERNEL_PATH
    rm -rf $KERNEL_PATH/out/arch/arm64/boot/*
    make O=out ARCH=arm64 $BUILD_CC $DEFCONFIG savedefconfig
    # Begin compilation
    start=$(date +%s)
    make O=out  CC=clang CXX=clang++ ARCH=arm64 -j`nproc` ${BUILD_CC} 2>&1 | tee error.log
    end=$(date +%s)
    build_time=$((end - start))
    if [ -f $KERNEL_PATH/out/arch/arm64/boot/Image ]; then
        echo -e "${green}Compilation successful!${clear}"
        echo -e "${green}Kernel build time: ${build_time} seconds${clear}"
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
    zip_name="OP9RT-v5.4.$(grep "^SUBLEVEL =" Makefile | awk '{print $3}')-$(date +"%Y%m%d").zip"
    cd $KERNEL_PATH/AnyKernel3
    cp $KERNEL_PATH/out/arch/arm64/boot/Image $KERNEL_PATH/AnyKernel3
    zip -r ${zip_name} *
    mv ${zip_name} $KERNEL_PATH/out/arch/arm64/boot
    echo -e "${green}Files are in $KERNEL_PATH/out/arch/arm64/boot${clear}"
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

if [ -d $CLANG_PATH ]; then
    echo -e "${blue}${folder} exists, Skipping !${clear}"
else
    echo -e "${red}${folder} is missing, Cloning...${clear}"
    echo -e "${yellow}This will take a while...${clear}"
    clone_tools
    distro_check
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