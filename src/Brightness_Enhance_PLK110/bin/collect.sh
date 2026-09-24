#!/system/bin/sh
# ==========================================================================
# 反馈页「提取配置文件」
#
# 用途：模块未适配的机型，或已适配机型出现未知问题时，提取显示相关的系统配置素材。
#
# 隐私设计：
#   * 只在**系统配置分区**里取显示/亮度相关文件，全程只读
#   * 绝不进入 /data/data、/data/user*、/data/media、/data/misc、
#     /sdcard/Android、/data/system（用户数据）
#   * **配置本体原样保留、不做脱敏** —— 那些应用名单来自 ROM/OTA/RUS 下发，
#     是全网统一的固定数据，也是研究亮度策略的核心素材
#   * 仅设备标识快照做 PII 级脱敏
#
# 输出保留原机目录结构，便于直接对照挂载路径。
# 写入范围：仅 /storage/emulated/0/Download 下本次生成的目录与压缩包。
# ==========================================================================

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules/Brightness_Enhance_PLK110

DEST=/storage/emulated/0/Download
TS=$(date +%Y%m%d-%H%M%S)
NAME=Brightness_Config_$TS
WORK=$DEST/$NAME
FILE=$DEST/$NAME.tar.gz

mkdir -p "$DEST" 2>/dev/null
rm -rf "$WORK" 2>/dev/null
mkdir -p "$WORK" 2>/dev/null
[ -d "$WORK" ] || { echo "RESULT=ERR|无法创建输出目录 $WORK"; exit 1; }

# 把 <src> 下匹配特征的文件按原目录结构镜像到 <WORK>/<base>。
# 用单条 find 覆盖全部特征（原来 5 目录 × 11 特征 = 55 次 find 进程，每次都走一遍 sdcardfs）。
# 刻意不含 '*nit*'：文件名里的 "i-nit" 会连 init*.rc 一起命中，实测多带 59 个与亮度无关的
# init 脚本；而真正需要的 ..._100nit.odf / ..._2nits_pGC.txt 面板标定都含 "_panel_"，
# 已被 '*panel*' 覆盖，去掉它不会丢素材。
grab() {
  src=$1
  base=$2
  [ -d "$src" ] || return 0
  find "$src" -maxdepth 2 -type f \( \
        -iname '*display*'    -o -iname '*brightness*' -o -iname '*panel*' \
     -o -iname '*demura*'     -o -iname '*dbvgain*'    -o -iname '*eyeprotect*' \
     -o -iname '*apollo*'     -o -iname '*backlight*'  -o -iname '*ltm*' \
     -o -iname '*hbm*' \) 2>/dev/null \
  | sort -u | while IFS= read -r f; do
    rel=${f#"$src"/}
    d="$WORK/$base/$(dirname "$rel")"
    mkdir -p "$d" 2>/dev/null
    cp -a "$f" "$d/" 2>/dev/null
  done
}

grab /my_product/vendor/etc my_product/vendor/etc
grab /vendor/etc          vendor/etc
grab /system_ext/etc      system_ext/etc
grab /odm/etc             odm/etc
grab /system/etc          system/etc

# 模块生效时，被覆盖的那几个文件看到的是模块内容；要拿纯原机版就先用 WebUI
# 「模块开关」关闭模块并重启（重启后这些路径读到即原机文件），再点本按钮。
# 这里额外把模块自身那份也收进来，便于对照"当前生效 vs 模块自带"。
if [ -d "$MODDIR/my_product/vendor/etc" ]; then
  mkdir -p "$WORK/_module/my_product/vendor" 2>/dev/null
  cp -a "$MODDIR/my_product/vendor/etc" "$WORK/_module/my_product/vendor/etc" 2>/dev/null
fi

# ---------- 元信息 ----------
META=$WORK/_meta
mkdir -p "$META" 2>/dev/null

{
  echo "== 设备属性 =="
  for p in ro.product.model ro.product.device ro.product.name ro.product.brand \
           ro.build.display.id ro.build.version.release ro.build.version.ota \
           ro.build.version.sdk ro.build.version.oplusrom ro.bootmode \
           oplus_region oplusboot.prjname ro.boot.hardware; do
    echo "$p=$(getprop $p 2>/dev/null)"
  done
  echo
  echo "== 面板标识（cmdline）=="
  cat /proc/cmdline 2>/dev/null | tr ' ' '\n' | grep -E 'dsi_display0|PanelID|PanelSN'
  echo
  echo "== 内核里的面板名 =="
  dmesg 2>/dev/null | grep -oE "mdss_dsi_panel_[A-Za-z0-9_]+" | sort -u | head -10
} > "$META/device.txt" 2>/dev/null

{
  echo "== 采集清单（相对路径 / 字节数）=="
  find "$WORK" -type f 2>/dev/null | sed "s|^$WORK/||" | while IFS= read -r r; do
    echo "$r  $(wc -c < "$WORK/$r" 2>/dev/null | tr -d ' ')"
  done
} > "$META/filelist.txt" 2>/dev/null

{
  echo "本包由模块 Brightness_Enhance_PLK110 的 WebUI「提取配置文件」生成。"
  echo
  echo "内容：该机型显示/亮度相关的系统配置（my_product / vendor / system_ext / odm / system），"
  echo "      按原机目录结构保留。"
  echo "隐私：仅读取系统配置分区，不含任何用户数据；配置本体未做改动。"
  echo "      _meta/device.txt 中的设备标识已做 PII 级脱敏。"
} > "$META/README.txt" 2>/dev/null

# 设备标识仅做 PII 级脱敏（保留属性名，便于定位机型）
sed -E -i \
  -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|cn|net|org|io|me|dev|edu|gov|xyz|top|info|app|co|local)([^A-Za-z0-9]|$)/<mail>\2/g' \
  -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z]{2,}([^A-Za-z0-9]|$)/<mail>\1/g' \
  -e 's/(^|[^0-9])1[3-9][0-9]{9}([^0-9]|$)/\1<num>\2/g' \
  "$META/device.txt" 2>/dev/null

# ---------- 打包 ----------
tar -czf "$FILE" -C "$DEST" "$NAME" 2>/dev/null

if [ -f "$FILE" ]; then
  SIZE=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
  N=$(find "$WORK" -type f 2>/dev/null | wc -l | tr -d ' ')
  rm -rf "$WORK" 2>/dev/null
  echo "RESULT=OK|$FILE|$SIZE|$NAME|$N"
else
  echo "RESULT=ERR|打包失败"
fi
exit 0
