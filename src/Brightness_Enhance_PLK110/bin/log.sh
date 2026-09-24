#!/system/bin/sh
# ==========================================================================
# 反馈页「读取日志」
#
# 采集诊断用的日志与状态快照，全部在**设备本地**完成分级脱敏后再打包到系统下载目录。
#
# 隐私设计（按「来源」而不是「关键词」划边界）：
#   * logcat 先按系统显示服务的 TAG 白名单收窄，再在结果里做关键词确认
#   * 脱敏分级：
#       PII 级（邮箱 / 手机号）  -> 所有快照
#       包名级（第三方应用标识） -> 仅日志与 dumpsys；属性/挂载快照不跑，
#                                  否则 ro.product.model 这类 key 会被一起抹掉
#   * 不采集 /data/data、/data/user*、/data/media、/data/misc、/sdcard/Android、
#     /data/system/** 以及 KSU 的 sulog*
#   * 脱敏报告只写条数，不回显被抹掉的原文
#
# 写入范围：仅 /storage/emulated/0/Download 下本次生成的目录与压缩包。
# ==========================================================================

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules/Brightness_Enhance_PLK110

DEST=/storage/emulated/0/Download
TS=$(date +%Y%m%d-%H%M%S)
NAME=Brightness_Log_$TS
WORK=$DEST/$NAME
FILE=$DEST/$NAME.tar.gz

mkdir -p "$DEST" 2>/dev/null
rm -rf "$WORK" 2>/dev/null
mkdir -p "$WORK" 2>/dev/null
[ -d "$WORK" ] || { echo "RESULT=ERR|无法创建输出目录 $WORK"; exit 1; }

# ---------- 采集：设备与面板基线（属性快照） ----------
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
} > "$WORK/device.txt" 2>/dev/null

# ---------- 采集：内核日志 ----------
dmesg > "$WORK/dmesg.txt" 2>/dev/null

# ---------- 采集：logcat（先按来源收窄，再按关键词确认） ----------
logcat -d -v threadtime 2>/dev/null \
  | grep -aiE 'SurfaceFlinger|DisplayPower|OplusDisplay|DisplayManager|AutomaticBrightness|BrightnessSynchronizer|LightsService|DisplayModeDirector|LightSensor|OplusFeatureUIR|ApolloService|dsi_panel|msm_drm|com.android.server.display' \
  | grep -aiE 'brightness|hbm|lux|dbv|panel|display|nit|backlight' \
  | tail -4000 > "$WORK/logcat.txt" 2>/dev/null

# ---------- 采集：dumpsys ----------
dumpsys display > "$WORK/dumpsys_display.txt" 2>/dev/null
dumpsys SurfaceFlinger --display-id > "$WORK/surfaceflinger.txt" 2>/dev/null

# ---------- 采集：背光 sysfs ----------
{
  for d in /sys/class/backlight/*/; do
    [ -d "$d" ] || continue
    echo "-- $d --"
    for f in max_brightness actual_brightness brightness type; do
      [ -f "$d$f" ] && echo "$f = $(cat "$d$f" 2>/dev/null)"
    done
  done
  echo
  echo "-- /sys/kernel/oplus_display 节点 --"
  ls /sys/kernel/oplus_display/ 2>/dev/null
} > "$WORK/backlight.txt" 2>/dev/null

# ---------- 采集：挂载关系 ----------
grep -iE 'my_product|overlay|/data ' /proc/mounts > "$WORK/mounts.txt" 2>/dev/null

# ---------- 采集：模块自身信息 ----------
cp "$MODDIR/module.prop" "$WORK/module.txt" 2>/dev/null
[ -f "$MODDIR/skip_mount" ] && echo "skip_mount=1" >> "$WORK/module.txt" 2>/dev/null

# ---------- 采集：连续采样（观察亮度变化） ----------
# 采样是主要耗时来源（每次 dumpsys + sleep），3 次足以看出变化趋势
{
  for i in 1 2 3; do
    echo "--- 采样 $i ---"
    dumpsys display 2>/dev/null | grep -E 'mLuxRecord|Display State=|Display Brightness=|mHbmStatsState=|mScreenBrightnessNormalMaximum|mScreenBrightnessRangeMaximum|mCachedBrightnessInfo'
    echo
    [ "$i" = 3 ] || sleep 1
  done
} > "$WORK/sample.txt" 2>/dev/null

# ---------- 脱敏 ----------
RPT=$WORK/SANITIZE.txt
{
  echo "== 脱敏报告（仅计数，不回显原文）=="
  echo "PII 级：邮箱 -> <mail>，11 位手机号 -> <num>"
  echo "包名级：第三方应用标识符 -> <pkg>（只作用于日志与 dumpsys）"
  echo
} > "$RPT" 2>/dev/null

pii() {
  sed -E -i \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|cn|net|org|io|me|dev|edu|gov|xyz|top|info|app|co|local)([^A-Za-z0-9]|$)/<mail>\2/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z]{2,}([^A-Za-z0-9]|$)/<mail>\1/g' \
    -e 's/(^|[^0-9])1[3-9][0-9]{9}([^0-9]|$)/\1<num>\2/g' \
    "$1" 2>/dev/null
}

pkg() {
  sed -E -i \
    -e 's/(^|[^A-Za-z0-9._])([A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+){2,})/\1<pkg>/g' \
    "$1" 2>/dev/null
}

# 一次 sed 同时做 PII 与包名两级（$2=1 才做包名级）；一次 awk 统计三类占位符行数。
# 原实现是每文件 1~2 次 sed + 3 次 grep，9 个文件起 40 多个进程，且每次都走一遍 sdcardfs。
sanitize() {
  if [ "$2" = "1" ]; then pii "$1"; pkg "$1"; else pii "$1"; fi
  echo "$3 : $(awk '/<mail>/{m++} /<num>/{n++} /<pkg>/{p++}
                      END{printf "mail=%d num=%d pkg=%d", m+0, n+0, p+0}' "$1" 2>/dev/null)" >> "$RPT" 2>/dev/null
}

for f in "$WORK"/*.txt; do
  [ -f "$f" ] || continue
  b=${f##*/}
  [ "$b" = "SANITIZE.txt" ] && continue
  case "$b" in
    device.txt|backlight.txt|mounts.txt|module.txt|sample.txt) sanitize "$f" 0 "$b" ;;  # 仅 PII 级
    *) sanitize "$f" 1 "$b" ;;
  esac
done

echo "（以上计数为含该占位符的行数；若为 0 表示未检出对应内容）" >> "$RPT" 2>/dev/null

# ---------- 打包 ----------
tar -czf "$FILE" -C "$DEST" "$NAME" 2>/dev/null

if [ -f "$FILE" ]; then
  SIZE=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
  rm -rf "$WORK" 2>/dev/null
  echo "RESULT=OK|$FILE|$SIZE|$NAME"
else
  echo "RESULT=ERR|打包失败"
fi
exit 0
