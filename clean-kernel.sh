#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
KEEP_COUNT=2
DRY_RUN=false
SKIP_CONFIRM=false

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Remove old kernel packages from Fedora Linux.

OPTIONS:
    -k, --keep N       Number of kernel versions to keep (default: 2)
    -n, --dry-run      Preview what would be removed without executing
    -y, --yes          Skip confirmation prompt
    -h, --help         Show this help message

EXAMPLES:
    $SCRIPT_NAME                    # Keep 2 latest kernels, ask for confirmation
    $SCRIPT_NAME -n                # Preview removals
    $SCRIPT_NAME -k 1              # Keep only the running kernel (not recommended)
    $SCRIPT_NAME -y                 # Remove without asking
    $SCRIPT_NAME -k 3 -n           # Keep 3 kernels, preview only

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -k|--keep)
                KEEP_COUNT="$2"
                if ! [[ "$KEEP_COUNT" =~ ^[0-9]+$ ]] || [[ "$KEEP_COUNT" -lt 1 ]]; then
                    echo "Error: --keep requires a positive number" >&2
                    exit 1
                fi
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                ;;
        esac
    done
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        echo "Error: Do not run this script as root. Use sudo." >&2
        exit 1
    fi
}

check_dnf() {
    if ! command -v dnf &>/dev/null; then
        echo "Error: dnf not found. This script is for Fedora Linux." >&2
        exit 1
    fi
}

get_running_kernel_version() {
    local full_version
    full_version=$(uname -r)
    echo "$full_version" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

get_kernel_packages() {
    local kernels
    mapfile -t kernels < <(dnf rq --installonly --latest-limit=-1 2>/dev/null)
    
    local all_pkgs=()
    for kernel in "${kernels[@]}"; do
        mapfile -t pkgs < <(rpm -qa | grep "^${kernel//+/\\+}" | grep -vE '^(kernel-headers|kernel-debug)' || true)
        all_pkgs+=("${pkgs[@]}")
    done
    
    printf '%s\n' "${all_pkgs[@]}"
}

get_nvidia_kmod_packages() {
    local -a kept_versions=("$@")
    local nvidia_pkgs
    mapfile -t nvidia_pkgs < <(rpm -qa 2>/dev/null | grep -E '^kmod-nvidia' || true)
    
    local to_remove=()
    for pkg in "${nvidia_pkgs[@]}"; do
        local should_keep=false
        for kept in "${kept_versions[@]}"; do
            if [[ "$pkg" == *"${kept}"* ]]; then
                should_keep=true
                break
            fi
        done
        [[ "$should_keep" == "false" ]] && to_remove+=("$pkg")
    done
    
    printf '%s\n' "${to_remove[@]}"
}

remove_old_kernels() {
    local keep_count="$1"
    local dry_run="$2"
    
    local running_kernel_version
    running_kernel_version=$(get_running_kernel_version)
    echo "Running kernel version: $running_kernel_version"
    echo "Keeping $keep_count kernel version(s)"
    echo
    
    local kernel_pkgs
    mapfile -t kernel_pkgs < <(get_kernel_packages)
    
    local unique_versions=()
    for pkg in "${kernel_pkgs[@]}"; do
        if [[ "$pkg" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            local ver="${BASH_REMATCH[1]}"
            local found=false
            for v in "${unique_versions[@]}"; do
                [[ "$v" == "$ver" ]] && found=true && break
            done
            [[ "$found" == "false" ]] && unique_versions+=("$ver")
        fi
    done
    
    IFS=$'\n' sorted_versions=($(sort -V <<<"${unique_versions[*]}"))
    unset IFS
    
    local to_remove_versions=("${sorted_versions[@]:0:${#sorted_versions[@]}-keep_count+1}")
    
    if [[ ${#to_remove_versions[@]} -eq 0 ]] || [[ -z "${to_remove_versions[*]}" ]]; then
        echo "No old kernel packages to remove."
        return 0
    fi
    
    local to_remove=()
    for pkg in "${kernel_pkgs[@]}"; do
        for ver in "${to_remove_versions[@]}"; do
            if [[ "$pkg" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && [[ "${BASH_REMATCH[1]}" == "$ver" ]]; then
                to_remove+=("$pkg")
                break
            fi
        done
    done
    
    local kept_full_versions=()
    for ver in "${sorted_versions[@]:${#sorted_versions[@]}-keep_count}"; do
        for pkg in "${kernel_pkgs[@]}"; do
            if [[ "$pkg" =~ ([0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.fc[0-9]+\..+) ]] && [[ "${BASH_REMATCH[1]}" == "$ver" ]]; then
                local full_ver="${BASH_REMATCH[0]}"
                local found=false
                for kv in "${kept_full_versions[@]}"; do
                    [[ "$kv" == "$full_ver" ]] && found=true && break
                done
                [[ "$found" == "false" ]] && kept_full_versions+=("$full_ver")
                break
            fi
        done
    done
    
    local nvidia_pkgs
    mapfile -t nvidia_pkgs < <(get_nvidia_kmod_packages "${kept_full_versions[@]}")
    to_remove+=("${nvidia_pkgs[@]}")
    
    if [[ ${#to_remove[@]} -eq 0 ]]; then
        echo "No old kernel or kmod-nvidia packages to remove."
        return 0
    fi
    
    echo "Packages to be removed:"
    printf '  %s\n' "${to_remove[@]}"
    echo
    
    local total_size
    total_size=$(sudo rpm --assumeno -e --justdb "${to_remove[@]}" 2>&1 | grep -oP '(?<=Total download size: )[0-9.]+[KMG]' | head -1 || echo "unknown")
    if [[ "$total_size" != "unknown" ]] && [[ -n "$total_size" ]]; then
        echo "Space to be freed: ~$total_size"
        echo
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] No changes were made."
        return 0
    fi
    
    if [[ ${#to_remove[@]} -gt 0 ]]; then
        sudo dnf remove -y "${to_remove[@]}" && echo "Cleanup completed." || echo "Cleanup failed."
    fi
}

main() {
    parse_args "$@"
    check_root
    check_dnf
    
    if [[ "$KEEP_COUNT" -eq 1 ]]; then
        echo "WARNING: Keeping only 1 kernel is not recommended."
        echo "If the new kernel fails, you may not be able to boot."
        echo "Consider using --keep 2 or higher for safety."
        echo
    fi
    
    remove_old_kernels "$KEEP_COUNT" "$DRY_RUN"
}

main "$@"
