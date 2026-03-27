# Fedora Kernel Cleaner

A simple script to safely remove old kernel packages from Fedora Linux, freeing up disk space.

## Features

- Removes old kernel packages while keeping the latest versions
- Removes old `kmod-nvidia` packages that don't match any kept kernel version
- Interactive nvidia cleanup prompt (or use flags to automate)
- Configurable kernel retention count
- Dry-run mode to preview removals
- Shows disk space to be freed

## Installation

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/anjarhariadi/fedora_kernel_cleaner/main/clean-kernel.sh -o ~/bin/clean-kernel
chmod +x ~/bin/clean-kernel
```

### Manual Install

```bash
git clone https://github.com/anjarhariadi/fedora_kernel_cleaner.git
cd fedora_kernel_cleaner
chmod +x clean-kernel.sh
sudo mv clean-kernel.sh /usr/local/bin/clean-kernel
```

## Usage

```bash
clean-kernel [OPTIONS]
```

### Options

| Option               | Description                                             |
| -------------------- | ------------------------------------------------------- |
| `-k, --keep N`      | Number of kernel versions to keep (default: 2)         |
| `-n, --dry-run`     | Preview what would be removed without executing         |
| `-y, --yes`         | Skip confirmation prompt                                |
| `-N, --include-nvidia` | Include old kmod-nvidia packages in removal          |
| `-x, --exclude-nvidia` | Exclude kmod-nvidia packages from removal            |
| `-h, --help`        | Show help message                                       |

### Examples

```bash
# Preview removals (keep 2 latest kernels)
clean-kernel -n

# Remove old kernels, asking for confirmation
clean-kernel

# Keep only the running kernel (not recommended)
clean-kernel -k 1

# Remove without asking (good for automation)
clean-kernel -y

# Keep 3 kernels, dry-run mode
clean-kernel -k 3 -n

# Skip kmod-nvidia cleanup
clean-kernel --exclude-nvidia

# Include nvidia packages, skip confirm
clean-kernel --include-nvidia -y
```

## Safety

- By default, keeps 2 kernel versions (current + 1 fallback)
- Always requires sudo privileges
- Shows exactly what will be removed before making changes
- Does not modify personal data or system configuration
- kmod-nvidia cleanup is optional (prompts by default, or use flags to control)

## Requirements

- Fedora Linux
- Bash 4.0+
- sudo privileges
- dnf package manager

## License

MIT License - see [LICENSE](LICENSE) for details.
