#!/bin/bash

# ──────────────────────────────────────────────────────────────
# Terminal Colors
# ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}${BOLD}→${NC} ${BLUE}$1${NC}"; }
success() { echo -e "${GREEN}${BOLD}✔${NC} ${GREEN}$1${NC}"; }
warn()    { echo -e "${YELLOW}${BOLD}!${NC} ${YELLOW}$1${NC}"; }
error()   { echo -e "${RED}${BOLD}✖${NC} ${RED}$1${NC}"; }
divider() { echo -e "${BOLD}──────────────────────────────────────────────${NC}"; }

# ──────────────────────────────────────────────────────────────
# clone_if_missing + clean_clone
# ──────────────────────────────────────────────────────────────
clone_if_missing() {
    local repo_url=$1 branch=$2 target_dir=$3
    [ -z "$repo_url" ] || [ -z "$branch" ] || [ -z "$target_dir" ] && {
        error "Usage: clone_if_missing <repo_url> <branch> <target_dir>"
        return 1
    }

    if [ ! -d "$target_dir" ]; then
        info "Cloning $target_dir..."
        git clone "$repo_url" -b "$branch" "$target_dir" -q \
            && success "Done cloning $target_dir." || {
            error "Failed to clone $repo_url."
            return 1
        }
    else
        warn "$target_dir already exists, skipping."
    fi
    return 0
}

clean_clone() {
    local repo_url=$1 branch=$2 target_dir=$3
    [ -z "$repo_url" ] || [ -z "$branch" ] || [ -z "$target_dir" ] && {
        error "Usage: clean_clone <repo_url> <branch> <target_dir>"
        return 1
    }

    info "Fresh cloning $target_dir from $branch..."
    [ -d "$target_dir" ] && rm -rf "$target_dir" && success "Removed $target_dir."
    git clone "$repo_url" -b "$branch" "$target_dir" -q && \
        success "Cloned $target_dir." || {
        error "Clone failed."
        return 1
    }
    return 0
}

# ──────────────────────────────────────────────────────────────
# Kernel Repo (fixed to Normal Perf)
# ──────────────────────────────────────────────────────────────
divider
info "Cloning kernel into kernel/xiaomi/sm8250..."
clone_if_missing "https://github.com/numanmushtaq01/android_kernel_xiaomi_sm8250" "axksu" "kernel/xiaomi/sm8250"
divider

# ──────────────────────────────────────────────────────────────
# Other Repos
# ──────────────────────────────────────────────────────────────
info "Setting up other repositories..."
clone_if_missing "https://github.com/numanmushtaq01/android_device_xiaomi_sm8250-common" "16.0" "device/xiaomi/sm8250-common"
clone_if_missing "https://github.com/numanmushtaq01/vendor_xiaomi_sm8250-common" "aosp-16" "vendor/xiaomi/sm8250-common"
clone_if_missing "https://github.com/numanmushtaq01/vendor_xiaomi_pipa" "bka" "vendor/xiaomi/pipa"
clone_if_missing "https://github.com/LineageOS/android_hardware_lineage_compat" "lineage-23.0" "hardware/lineage/compat"
clone_if_missing "https://github.com/LineageOS/android_hardware_lineage_interfaces" "lineage-23.0" "hardware/lineage/interfaces"
clone_if_missing "https://github.com/LineageOS/android_hardware_lineage_livedisplay" "lineage-23.0" "hardware/lineage/livedisplay"
clone_if_missing "https://github.com/PocoF3Releases/device_qcom_wfd.git" "bka" "device/qcom/wfd"
clone_if_missing "https://github.com/PocoF3Releases/vendor_qcom_wfd.git" "bka" "vendor/qcom/wfd"
clean_clone "https://github.com/gensis01/hardware_xiaomi.git"  "aosp-16" "hardware/xiaomi"
clean_clone "https://github.com/PocoF3Releases/packages_resources_devicesettings.git" "aosp-16" "packages/resources/devicesettings"
divider

# ──────────────────────────────────────────────────────────────
# Apply Recovery Patch (non-fatal warning only)
# ──────────────────────────────────────────────────────────────
apply_recovery_patch() {
    local root_dir
    root_dir=$(pwd)
    local target_dir="bootable/recovery"
    local patch_file="$root_dir/device/xiaomi/pipa/source-patches/atomic-recovery.diff"
    local temp_patch="/tmp/atomic-recovery.patch"

    info "Attempting to apply recovery patch..."

    if [ ! -f "$patch_file" ]; then
        warn "Patch file not found, skipping: $patch_file"
        return
    fi

    if ! cd "$target_dir"; then
        warn "Could not enter $target_dir, skipping patch."
        return
    fi
    
    tr -d '\r' < "$patch_file" > "$temp_patch"

    local patch_fingerprint
    patch_fingerprint=$(sha1sum "$temp_patch" | awk '{print $1}')
    if git log -1 --pretty=%B | grep -q "$patch_fingerprint"; then
        warn "Recovery patch seems to be already applied. Skipping."
        rm -f "$temp_patch"
        cd "$root_dir"
        return
    fi

    if git apply --check --ignore-whitespace "$temp_patch" >/dev/null 2>&1; then
        git apply --ignore-whitespace "$temp_patch"
        git add .
        git commit -m "Apply recovery patch: $patch_fingerprint" -q
        success "Recovery patch applied successfully."
    else
        warn "White recovery patch is skipped, may cause problems in recovery."
    fi

    rm -f "$temp_patch"
    cd "$root_dir"
}

# ──────────────────────────────────────────────────────────────
# Setup firmware
# ──────────────────────────────────────────────────────────────
setup_firmware() {
    local root_dir
    root_dir=$(pwd)
    local target_dir="${root_dir}/vendor/xiaomi/pipa"
    local firmware_url="https://github.com/numanmushtaq01/vendor_xiaomi_pipa/vendor_xiaomi_pipa/releases/download/pipa-2/pipa-2.0.12.0-MI.zip"
    local tmp_zip="/tmp/pipa-2.0.12.0-MI.zip"
    local tmp_extract="/tmp/firmware_extract"

    info "Setting up firmware..."

    mkdir -p "$target_dir" || {
        error "Failed to create target directory: $target_dir"
        return 1
    }

    if [ -d "$target_dir/radio" ]; then
        warn "Removing existing radio folder..."
        rm -rf "$target_dir/radio" || {
            error "Failed to remove existing $target_dir/radio"
            return 1
        }
    fi

    if command -v curl >/dev/null 2>&1; then
        info "Downloading firmware (curl)..."
        curl -L --fail -o "$tmp_zip" "$firmware_url" || {
            error "Failed to download firmware with curl."
            [ -f "$tmp_zip" ] && rm -f "$tmp_zip"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        info "Downloading firmware (wget)..."
        wget -q -O "$tmp_zip" "$firmware_url" || {
            error "Failed to download firmware with wget."
            [ -f "$tmp_zip" ] && rm -f "$tmp_zip"
            return 1
        }
    else
        error "Neither curl nor wget found. Cannot download firmware."
        return 1
    fi

    rm -rf "$tmp_extract"
    mkdir -p "$tmp_extract" || {
        error "Failed to create temp extract dir: $tmp_extract"
        rm -f "$tmp_zip"
        return 1
    }

    if command -v unzip >/dev/null 2>&1; then
        info "Extracting firmware into temporary location..."
        unzip -q -o "$tmp_zip" -d "$tmp_extract" || {
            error "Extraction failed with unzip."
            rm -f "$tmp_zip"
            rm -rf "$tmp_extract"
            return 1
        }
    elif command -v bsdtar >/dev/null 2>&1; then
        info "Extracting firmware with bsdtar..."
        bsdtar -xf "$tmp_zip" -C "$tmp_extract" || {
            error "Extraction failed with bsdtar."
            rm -f "$tmp_zip"
            rm -rf "$tmp_extract"
            return 1
        }
    else
        error "No extractor (unzip or bsdtar) available."
        rm -f "$tmp_zip"
        rm -rf "$tmp_extract"
        return 1
    fi

    local radio_dir
    radio_dir=$(find "$tmp_extract" -type d -name radio -print -quit)

    if [ -z "$radio_dir" ]; then
        error "No 'radio' directory found inside the extracted firmware."
        rm -f "$tmp_zip"
        rm -rf "$tmp_extract"
        return 1
    fi

    info "Moving radio directory into $target_dir..."
    mv "$radio_dir" "$target_dir"/ || {
        error "Failed to move radio directory to $target_dir"
        rm -f "$tmp_zip"
        rm -rf "$tmp_extract"
        return 1
    }

    rm -f "$tmp_zip"
    rm -rf "$tmp_extract"

    success "Firmware setup complete: moved 'radio' directory to $target_dir/radio"
}

# ──────────────────────────────────────────────────────────────
# Apply FWB Patch (Tablet, Local)
# ──────────────────────────────────────────────────────────────
apply_fwb_patch() {
    local root_dir
    root_dir=$(pwd)
    local target_dir="frameworks/base"
    local patch_file="$root_dir/device/xiaomi/pipa/patches/tablet-fwb.patch"

    info "Applying Tablet FWB patch from local repo..."

    if [ ! -f "$patch_file" ]; then
        error "Patch file not found: $patch_file"
        return 1
    fi

    if ! cd "$target_dir"; then
        error "Could not enter $target_dir to apply patch."
        return 1
    fi

    if git apply --check --ignore-whitespace "$patch_file" >/dev/null 2>&1; then
        git apply --ignore-whitespace "$patch_file"
        success "Tablet FWB patch applied successfully."
    else
        warn "Tablet FWB patch could not be applied (may already be applied or conflict)."
    fi

    cd "$root_dir"
}

# ──────────────────────────────────────────────────────────────
# Run Patch Setup
# ──────────────────────────────────────────────────────────────
ROOT_DIR=$(pwd)
DEVICE_PATH="${ROOT_DIR}/device/xiaomi/pipa"
mkdir -p "$DEVICE_PATH/source-patches"

apply_recovery_patch
setup_firmware
apply_fwb_patch

echo "-------------------------------------"
echo "           Setup complete!           "
echo "-------------------------------------"
