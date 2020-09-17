KERNEL_DIR=$PWD
KERNEL="Image.gz-dtb"
KERN_IMG=$KERNEL_DIR/out/arch/arm64/boot/Image.gz-dtb
BUILD_START=$(date +"%s")
ANYKERNEL_DIR=/home/shanu/AnyKernel3
EXPORT_DIR=/home/shanu/flashablezips

# Make Changes to this before release
ZIP_NAME="Noodle-perf+"

# Color Code Script
Black='\e[0;30m'        # Black
Red='\e[0;31m'          # Red
Green='\e[0;32m'        # Green
Yellow='\e[0;33m'       # Yellow
Blue='\e[0;34m'         # Blue
Purple='\e[0;35m'       # Purple
Cyan='\e[0;36m'         # Cyan
White='\e[0;37m'        # White
nocol='\033[0m'         # Default

# Tweakable Options Below
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="galanteria01"
export KBUILD_BUILD_HOST="Host"
export CROSS_COMPILE="/home/shanu/proton-clang"
export KBUILD_COMPILER_STRING=$(/root/platform_prebuilts_clang_host_linux-x86/clang-r328903/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
                                       "


# Compilation Scripts Are Below
echo -e "${Green}"
echo "-----------------------------------------------"
echo "  Initializing build to compile Ver: $ZIP_NAME    "
echo "-----------------------------------------------"

echo -e "$Yellow***********************************************"
echo "         Creating Output Directory: out      "
echo -e "***********************************************$nocol"

mkdir -p out

echo -e "$Yellow***********************************************"
echo "          Cleaning Up Before Compile          "
echo -e "***********************************************$nocol"

make O=out clean 
make O=out mrproper

echo -e "$Yellow***********************************************"
echo "          Initialising DEFCONFIG        "
echo -e "***********************************************$nocol"

make O=out ARCH=arm64 violet-perf_defconfig

echo -e "$Yellow***********************************************"
echo "          Cooking Noodle        "
echo -e "***********************************************$nocol"

make -j$(nproc --all) O=out ARCH=arm64 \
		      CC="/home/shanu/platform_prebuilts_clang_host_linux-x86/clang-r328903/bin/clang" \
                      CLANG_TRIPLE="aarch64-linux-gnu-"

# If the above was successful
if [ -a $KERN_IMG ]; then
   BUILD_RESULT_STRING="BUILD SUCCESSFUL"

echo -e "$Purple***********************************************"
echo "       Making Flashable Zip       "
echo -e "***********************************************$nocol"
   # Make the zip file
   echo "MAKING FLASHABLE ZIP"

   cp -vr ${KERN_IMG} ${ANYKERNEL_DIR}/zImage
   cd ${ANYKERNEL_DIR}
   zip -r9 ${ZIP_NAME}.zip * -x README ${ZIP_NAME}.zip

else
   BUILD_RESULT_STRING="BUILD FAILED"
fi

NOW=$(date +"%m-%d")
ZIP_LOCATION=${ANYKERNEL_DIR}/${ZIP_NAME}.zip
ZIP_EXPORT=${EXPORT_DIR}/${NOW}
ZIP_EXPORT_LOCATION=${EXPORT_DIR}/${NOW}/${ZIP_NAME}.zip

rm -rf ${ZIP_EXPORT}
mkdir ${ZIP_EXPORT}
mv ${ZIP_LOCATION} ${ZIP_EXPORT}
cd ${HOME}

# End the script
echo "${BUILD_RESULT_STRING}!"

# BUILD TIME
BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "$Yellow Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
