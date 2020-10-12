#!/usr/bin/env zsh
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2017-2020 Nathan Chancellor
#
# Script to build a zImage from a kernel tree

######################
#                    #
#  HELPER FUNCTIONS  #
#                    #
######################

# Get cross compile prefix
function get_cc_prefix() {
    find "${1}" \( -type f -o -type l \) -name '*-gcc' -printf "%T+\t%p\n" | sort -r | head -n1 | sed 's@.*/@@' | sed 's/real-//' | sed 's/gcc//'
}

# Kernel make function
function kmake() {
    # Set make variable
    MAKE=(make "${JOBS_FLAG}" O=out ARCH="${ARCH}")

    if [[ -n ${CLANG} ]]; then
        "${MAKE[@]}" \
            CC="${CCACHE} clang" \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CLANG_TRIPLE_ARM32=arm-linux-gnueabi- \
            CROSS_COMPILE="${GCC_CC}" \
            CROSS_COMPILE_ARM32="${GCC_32_BIT_CC}" \
            PYTHON="$(command -v python2 || command -v python2.7)" \
            "${@}"
    else
        "${MAKE[@]}" \
            CROSS_COMPILE="${CCACHE} ${GCC_CC}" \
            CROSS_COMPILE_ARM32="${GCC_32_BIT_CC}" \
            PYTHON="$(command -v python2 || command -v python2.7)" \
            "${@}"
    fi
}

#######################
#                     #
#  PRIMARY FUNCTIONS  #
#                     #
#######################

# Gather parameters
function parse_parameters() {
    PARAMS="${*}"
    START=$(date +%s)
    while ((${#})); do
        case ${1} in
            -a | --arch)
                # Architecture to build
                shift && enforce_value "${@}"

                ARCH=${1}
                ;;

            -c | --clang)
                # Use Clang for compiling the kernel
                CLANG=true
                ;;

            -ct | --clang-toolchain)
                # Specify which Clang toolchain to use
                shift && enforce_value "${@}"

                CLANG_FOLDER=${1}
                ;;

            -d | --defconfig)
                # Config to build
                shift && enforce_value "${@}"

                IFS=',' read -r -A DEFCONFIGS <<<"${1}"
                ;;

            -D | --debug)
                # Show full compilation
                VERBOSITY=3
                ;;

            -e | --errors)
                # Only show errors
                VERBOSITY=1
                RG_LOOK_FOR="error:"
                ;;

            -f | --folder)
                # Kernel folder
                shift && enforce_value "${@}"

                FOLDER=${1}
                ;;

            -gt | --gcc-toolchain)
                # Specify which GCC toolchain to use
                shift && enforce_value "${@}"

                GCC_FOLDER=${1}
                ;;

            -gt-32 | --gcc-32-bit-toolchain)
                # 32-bit GCC toolchain to use for compiling
                shift && enforce_value "${@}"

                GCC_32_BIT_FOLDER=${1}
                ;;

            -r | --show-only-result)
                # Just show if build was successful or not
                SHOW_ONLY_RESULT=true
                ;;

            -v | --version-display)
                # Version to display
                shift && enforce_value "${@}"

                VERSION_DISPLAY=${1}
                ;;

            -w | --warnings)
                # Show only warnings and errors during compilation
                VERBOSITY=2
                RG_LOOK_FOR="error:|warning:"
                ;;

            -Werror)
                # Compile with -Werror
                WERROR=true
                ;;

            -Wno-error)
                # Disable -Werror
                NO_WERROR=true
                ;;
        esac

        shift
    done

    # Error out if we aren't in a tree with a Makefile
    if [[ -n ${FOLDER} ]]; then
        cd "${FOLDER}" || die "Folder requested doesn't exist!"
    fi
    [[ ! -f Makefile ]] && die "This must be run in a kernel tree!"

    # Error out if defconfig wasn't supplied
    [[ ${#DEFCONFIGS[@]} -lt 1 ]] && die "Please supply a defconfig!"

    # Defaults
    [[ -z ${ARCH} ]] && ARCH=arm64
    [[ -z ${GCC_FOLDER} ]] && GCC_FOLDER=${ANDROID_TC_FOLDER}/gcc-${ARCH}
}

# Set toolchain paths
function setup_toolchains() {
    # GCC (64-bit or 32-bit)
    if [[ ! -d ${GCC_FOLDER} ]]; then
        GCC_FOLDER=${ANDROID_TC_FOLDER}/${GCC_FOLDER}
        [[ ! -d ${GCC_FOLDER} ]] && die "Invalid 64-bit GCC folder specified!"
    fi
    GCC_BIN=${GCC_FOLDER}/bin
    GCC_CC=$(get_cc_prefix "${GCC_BIN}")
    [[ -z ${GCC_CC} ]] && die "64-bit GCC toolchain could not be found!"

    # GCC 32-bit for compat VDSO
    if [[ -d arch/arm64/kernel/vdso32 ]]; then
        [[ -z ${GCC_32_BIT_FOLDER} ]] && GCC_32_BIT_FOLDER=${ANDROID_TC_FOLDER}/gcc-arm
        if [[ ! -d ${GCC_32_BIT_FOLDER} ]]; then
            GCC_32_BIT_FOLDER=${ANDROID_TC_FOLDER}/${GCC_32_BIT_FOLDER}
            [[ ! -d ${GCC_32_BIT_FOLDER} ]] && die "Invalid 32-bit GCC folder specified!"
        fi
        GCC_32_BIT_BIN=${GCC_32_BIT_FOLDER}/bin
        GCC_32_BIT_CC=$(get_cc_prefix "${GCC_32_BIT_BIN}")
        [[ -z ${GCC_32_BIT_CC} ]] && die "32-bit GCC toolchain could not be found!"
    fi

    # Clang
    if [[ -n ${CLANG} ]]; then
        [[ -z ${CLANG_FOLDER} ]] && CLANG_FOLDER=${ANDROID_TC_FOLDER}/clang-r353983c
        if [[ ! -d ${CLANG_FOLDER} ]]; then
            CLANG_FOLDER=${ANDROID_TC_FOLDER}/${CLANG_FOLDER}
            [[ ! -d ${CLANG_FOLDER} ]] && die "Invalid Clang folder specified!"
        fi
        CLANG_BIN=${CLANG_FOLDER}/bin
        [[ ! -f ${CLANG_BIN}/clang ]] && die "Clang binary could not be found!"

        # LD_LIBRARY_PATH is needed for LTO
        LD_LIBRARY_PATH=$(find "${CLANG_FOLDER}" -maxdepth 1 -name 'lib' -o -name 'lib64' -type d)${LD_LIBRARY_PATH:+":${LD_LIBRARY_PATH}"}
        export LD_LIBRARY_PATH
    fi

    PATH=${CLANG_BIN:+"${CLANG_BIN}:"}${GCC_BIN}:${GCC_32_BIT_BIN:+"${GCC_32_BIT_BIN}:"}:${PATH}
    export PATH
}

# Basic build function
function build() {
    # Clean up from last compile
    rm -rf out && mkdir -p out

    # Build kernel image
    if [[ ${#DEFCONFIGS[@]} -gt 1 ]]; then
        cat "${DEFCONFIGS[@]}" >out/.config
        kmake olddefconfig |& rg --color=never -v "format-overflow"
    else
        kmake "${DEFCONFIGS[1]}" |& rg --color=never -v "format-overflow"
    fi
    if [[ -n ${WERROR} ]]; then
        ./scripts/config --file out/.config -e CC_WERROR -e CONFIG_ERROR_ON_WARNING
        kmake olddefconfig
    fi
    if [[ -n ${NO_WERROR} ]]; then
        ./scripts/config --file out/.config -d CC_WERROR -d CONFIG_ERROR_ON_WARNING
        kmake olddefconfig
    fi
    if [[ "${PWD}" =~ "op6" ]]; then
        ./scripts/config --file out/.config -e BUILD_ARM64_DT_OVERLAY
        kmake olddefconfig
        NEEDS_EXTERNAL_DTC=true
    fi

    kmake ${NEEDS_EXTERNAL_DTC:+ DTC_EXT="dtc -f"} |& rg --color=never -v "dts"
}

# Compilation function
function compile() {
    # Start hiding output
    [[ -n ${SHOW_ONLY_RESULT} ]] && exec >/dev/null

    # Show the base version we are making
    header "BUILDING $(make -s CROSS_COMPILE="" CC=gcc kernelversion)"

    # Show compilation based on flags
    case ${VERBOSITY} in
        3)
            build
            ;;
        1 | 2)
            DISABLED_WARNINGS=(
                "which has unmet direct dependencies"
                "choice value used outside its choice group"
                "reassigning to symbol"
                "changes choice state"
            )
            for ITEM in "${DISABLED_WARNINGS[@]}"; do RG_IGNORE="${RG_IGNORE}${ITEM}|"; done
            build |& rg --color=never "${RG_LOOK_FOR}" |& rg -v "${RG_IGNORE/%|/}"
            ;;
        *)
            build &>/dev/null
            ;;
    esac

    # Find final image
    FINAL_IMAGE=$(find out -name 'Image*-dtb')
    [[ -z ${FINAL_IMAGE} ]] && FINAL_IMAGE=$(find out -name 'Image.*' | tail -1)
    [[ -z ${FINAL_IMAGE} ]] && FINAL_IMAGE=$(find out -name 'Image*' | tail -1)
}

# Report success
function report_result() {
    TIME_STRING=$(format_time "${START}" "$(date +%s)")
    [[ -n ${SHOW_ONLY_RESULT} ]] && SCRIPT_COMMAND="${SCRIPT_NAME} ${PARAMS}  |  "
    if [[ -f ${FINAL_IMAGE} ]]; then
        echo
        printf '%s%bBuild successful in %s%b\n' "${SCRIPT_COMMAND}" "${GRN}" "${TIME_STRING}" "${RST}" >&2
        echo
        printf '%bImage:%b      %s\n' "${BOLD}" "${RST}" "${FINAL_IMAGE}"
        echo
        formatted_kernel_version "${VERSION_DISPLAY}"
    else
        printf '%s%bBuild failed in %s%b\n' "${SCRIPT_COMMAND}" "${RED}" "${TIME_STRING}" "${RST}" >&2
        exit 33
    fi

    # Alert of script end
    printf '\a'

    exit 0
}

source "${SCRIPTS_FOLDER}/common"
source "${SCRIPTS_FOLDER}/env/stubs/folders"
source "${SCRIPTS_FOLDER}/env/stubs/fkv"
source "${SCRIPTS_FOLDER}/env/stubs/traps"
SCRIPT_NAME=${0##*/}
parse_parameters "${@}"
setup_toolchains
compile
report_result
