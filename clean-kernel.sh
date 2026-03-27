#!/usr/bin/env bash
set -euo pipefail

# Take kernel version from running kernel (the active kerne)
RUNNING_KERNEL_FULL=$(uname -r)
RUNNING_KERNEL_VERSION=$(echo "$RUNNING_KERNEL_FULL" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

echo "Running kernel version detected: $RUNNING_KERNEL_VERSION"

# List of packages to be removed
PKG_PREFIXES=(
  kernel
  kernel-core
  kernel-devel
  kernel-devel-matched
  kernel-modules
  kernel-modules-core
  kernel-modules-extra
  kernel-tools
  kernel-tools-libs
  kmod-nvidia
)

# Packages to be excluded
EXCLUDE_PKGS=(
  kernel-headers
)

mapfile -t CANDIDATE_PKGS < <(
  rpm -qa | grep -E "^($(IFS='|'; echo "${PKG_PREFIXES[*]}"))"
)

TO_REMOVE=()

for pkg in "${CANDIDATE_PKGS[@]}"; do
  # Skip the excluded packages
  for exclude in "${EXCLUDE_PKGS[@]}"; do
    [[ "$pkg" == $exclude-* ]] && continue 2
  done

  if [[ "$pkg" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    PKG_VERSION="${BASH_REMATCH[1]}"
    if [[ "$PKG_VERSION" != "$RUNNING_KERNEL_VERSION" ]]; then
      TO_REMOVE+=("$pkg")
    fi
  fi
done

if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
  echo "No old kernel or kmod-nvidia packages to remove."
  exit 0
fi

echo "Packages to be removed:"
printf '  %s\n' "${TO_REMOVE[@]}"

echo
read -rp "Proceed with removal? [y/N]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  sudo dnf remove -y "${TO_REMOVE[@]}"
  echo "Cleanup completed."
else
  echo "Aborted."
fi
