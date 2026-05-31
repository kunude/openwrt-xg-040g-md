#!/bin/bash
set -e

echo "Installing Patches..."

# 确保 openwrt 目录存在
if [ ! -d "$GITHUB_WORKSPACE/openwrt" ]; then
    echo "❌ openwrt directory not found!"
    exit 1
fi

# 复制补丁
cp -rf "$GITHUB_WORKSPACE/patch/target/." "$GITHUB_WORKSPACE/openwrt/target"
cat "$GITHUB_WORKSPACE/openwrt/target/linux/airoha/an7581/base-files/lib/upgrade/platform.sh"

# ============================================
# 添加 fw_env.config，确保 MAC 地址首次随机生成后永久固定
# ============================================
echo "Adding fw_env.config..."

mkdir -p "$GITHUB_WORKSPACE/openwrt/files/etc"
cat << 'EOF' > "$GITHUB_WORKSPACE/openwrt/files/etc/fw_env.config"
/dev/mtd1 0x00000 0x80000 0x20000 4
EOF

echo "✓ fw_env.config added successfully"
