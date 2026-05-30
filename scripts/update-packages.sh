#!/bin/bash
# 安装和更新第三方软件包
# 此脚本在 openwrt/package/ 目录下运行，在 feeds install 之后执行

UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo " "
	echo "=========================================="
	echo "Processing: $PKG_NAME from $PKG_REPO"
	echo "=========================================="

	# 删除 feeds 中可能存在的同名软件包
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	if [ ! -d "$REPO_NAME" ]; then
		echo "ERROR: Failed to clone $PKG_REPO"
		return 1
	fi

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 从大杂烩仓库中提取特定包
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		# 重命名仓库
		mv -f $REPO_NAME $PKG_NAME
	fi

	echo "Done: $PKG_NAME"
}

PATCH_PASSWALL_GLOBAL_LUA() {
	local CANDIDATES=(
		"./luci-app-passwall/luasrc/model/cbi/passwall/client/global.lua"
		"./passwall/luci-app-passwall/luasrc/model/cbi/passwall/client/global.lua"
	)
	local FOUND=0

	for FILE in "${CANDIDATES[@]}"; do
		if [ -f "$FILE" ]; then
			FOUND=1
			echo "Applying PassWall Lua compatibility hotfix: $FILE"

			# Guard optional form fields to avoid nil-index runtime errors.
			sed -i 's#local dns_shunt_val = s.fields\["dns_shunt"\]:formvalue(section)#local dns_shunt_val = (s.fields["dns_shunt"] and s.fields["dns_shunt"]:formvalue(section)) or ""#g' "$FILE"
			sed -i 's#s.fields\["dns_mode"\]:formvalue(section) == "xray" or s.fields\["smartdns_dns_mode"\]:formvalue(section) == "xray"#((s.fields["dns_mode"] and s.fields["dns_mode"]:formvalue(section)) == "xray") or ((s.fields["smartdns_dns_mode"] and s.fields["smartdns_dns_mode"]:formvalue(section)) == "xray")#g' "$FILE"
			sed -i 's#s.fields\["dns_mode"\]:formvalue(section) == "sing-box" or s.fields\["smartdns_dns_mode"\]:formvalue(section) == "sing-box"#((s.fields["dns_mode"] and s.fields["dns_mode"]:formvalue(section)) == "sing-box") or ((s.fields["smartdns_dns_mode"] and s.fields["smartdns_dns_mode"]:formvalue(section)) == "sing-box")#g' "$FILE"
		fi
	done

	if [ "$FOUND" -eq 0 ]; then
		echo "WARNING: PassWall global.lua not found, hotfix skipped."
	fi
}

echo "Starting package updates..."

# 首先删除 feeds 中的 sing-box 相关包，避免与第三方包冲突
echo " "
echo "=========================================="
echo "Removing conflicting sing-box packages from feeds..."
echo "=========================================="
rm -rf ../feeds/packages/net/sing-box
rm -rf ../package/feeds/packages/sing-box
echo "Done removing sing-box from feeds"

# HomeProxy (代理软件) - 使用第5个参数指定额外要删除的包名
# UPDATE_PACKAGE "homeproxy" "immortalwrt/homeproxy" "master"

# Argon 主题
# UPDATE_PACKAGE "luci-theme-argon" "jerrykuku/luci-theme-argon" "master"
# UPDATE_PACKAGE "luci-app-argon-config" "jerrykuku/luci-app-argon-config" "master"
# ddns-go 和 luci-app-ddns-go
# UPDATE_PACKAGE "luci-app-ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "luci-app-airoha-npu" "kunude/luci-app-airoha-npu" "main"


# 修改luci-app-airoha-npu插件的Makefile（不修改编译的时候会找不到路径报错）
# vi luci-app-airoha-npu/Makefile
# include $(TOPDIR)/feeds/luci/luci.mk

# 修改 LuCI 默认主题为 Argon（保留 bootstrap 包可共存）
# echo " "
# echo "=========================================="
# echo "Setting default LuCI theme to argon..."
# echo "=========================================="
# COLLECTION_MAKEFILES=$(find ../feeds/luci/collections/ -type f -name "Makefile" 2>/dev/null)
# if [ -n "$COLLECTION_MAKEFILES" ]; then
# 	sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $COLLECTION_MAKEFILES
# 	echo "Done setting default LuCI theme to argon"
# else
# 	echo "WARNING: No LuCI collection Makefile found, skip theme default patch"
# fi

# PassWall (代理软件)
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"
PATCH_PASSWALL_GLOBAL_LUA

# OpenWrt 25.12 下 shadowsocksr-libev 的上游归档内容已变化，旧 MIRROR_HASH 失效。
# 先禁用 SSR 组件，避免 passwall 选择该包导致下载阶段直接失败。
PASSWALL_MAKEFILE="./luci-app-passwall/Makefile"
 if [ -f "$PASSWALL_MAKEFILE" ]; then
 	echo "Patching PassWall defaults to disable broken ShadowsocksR components..."
 	sed -i '/config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Client/,/default y/s/default y/default n/' "$PASSWALL_MAKEFILE"
 	sed -i '/config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Server/,/default n/s/default n/default n/' "$PASSWALL_MAKEFILE"
 fi

# PassWall 依赖包
# echo " "
# echo "=========================================="
# echo "Installing PassWall dependencies..."
# echo "=========================================="
 git clone --depth=1 --single-branch --branch main "https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"
 if [ -d "openwrt-passwall-packages" ]; then
 	for pkg in openwrt-passwall-packages/*/; do
 		pkg_name=$(basename "$pkg")
 		if [ -d "$pkg" ] && [ -f "$pkg/Makefile" ]; then
 			echo "Installing: $pkg_name"
 			rm -rf "./$pkg_name"
 			cp -rf "$pkg" ./
 		fi
 	done
 	rm -rf openwrt-passwall-packages
 fi

# echo "Installing emortal packages..."
# echo "=========================================="
# unzip emortal.zip -d ./emortal
# rm emortal.zip
# ls emortal

# ==========================================
# 添加 ddns-go 和 luci-app-ddns-go
# ==========================================

echo "Cloning ddns-go and luci-app-ddns-go from kenzok8/small-package..."
git clone --depth 1 https://github.com/kenzok8/small-package.git temp_package

# 查找并复制（处理可能的目录名差异）
for dir in temp_package/ddns-go temp_package/luci-app-ddns-go temp_package/luci-app-ddnsgo; do
    if [ -d "$dir" ]; then
        name=$(basename "$dir")
        cp -rf "$dir" ./${name#temp_package/}
        echo "Copied: $dir -> ./$name"
    fi
done
rm -rf temp_package

# 验证复制结果
echo "=== Verifying ddns packages ==="
ls -ld ./*ddns* 2>/dev/null || echo "WARNING: No ddns packages found"

# ==========================================
# 修复 ddns-go 启动脚本和 Makefile
# ==========================================

echo "Patching ddns-go..."

# 1. 创建默认配置文件（启动脚本依赖）
DDNSGO_FILEDIR="./ddns-go/file"
mkdir -p "$DDNSGO_FILEDIR"

cat > "$DDNSGO_FILEDIR/ddns-go-default.yaml" << 'EOF'
ipv4:
  enable: true
  gettype: url
  url: https://myip.ipip.net,https://ddns.oray.com/checkip,https://ip.3322.net,https://4.ipw.cn
  domains:
    - ""
dns:
  name: ""
  id: ""
  secret: ""
EOF
echo "Created ddns-go-default.yaml"

# 2. 修改 Makefile，安装默认配置文件到 /usr/share/ddns-go/
DDNSGO_MAKEFILE="./ddns-go/Makefile"
if [ -f "$DDNSGO_MAKEFILE" ]; then
    # 在 uci-defaults 安装后添加 default yaml 安装
    sed -i '/$(INSTALL_BIN) $(CURDIR)\/file\/luci-ddns-go.uci-default/a\
\
\t$(INSTALL_DIR) $(1)/usr/share/ddns-go\
\t$(INSTALL_CONF) $(CURDIR)/file/ddns-go-default.yaml $(1)/usr/share/ddns-go/ddns-go-default.yaml' "$DDNSGO_MAKEFILE"
    echo "Patched Makefile to install default config"
fi

# 3. 修复启动脚本，添加兜底配置（防止文件不存在时启动失败）
DDNSGO_INIT="./ddns-go/file/ddns-go.init"
if [ -f "$DDNSGO_INIT" ]; then
    # 备份原文件
    cp "$DDNSGO_INIT" "$DDNSGO_INIT.bak"
    
    # 重写 init_yaml 函数，添加兜底逻辑
    sed -i '/^init_yaml(){/,/^}/c\
init_yaml(){\
\t[ -d $CONFDIR ] || mkdir -p $CONFDIR 2>/dev/null\
\tif [ -f /usr/share/ddns-go/ddns-go-default.yaml ]; then\
\t\tcat /usr/share/ddns-go/ddns-go-default.yaml > $CONF\
\telse\
\t\tcat > $CONF << '\''EOFYAML'\''\
ipv4:\
  enable: true\
  gettype: url\
  url: https://myip.ipip.net\
  domains:\
    - ""\
dns:\
  name: ""\
  id: ""\
  secret: ""\
EOFYAML\
\tfi\
}' "$DDNSGO_INIT"
    echo "Patched init script with fallback config"
fi

echo "Done patching ddns-go"
echo " "
echo "=========================================="
echo "Package updates completed!"
echo "=========================================="
