#!/system/bin/sh
# ==========================================================================
# Brightness_Enhance_PLK110 —— 供 WebUI 读取的实时状态（**全程只读**）
#
# 输出：每行一个 key=value，便于前端解析。
# 数据来源：
#   * dumpsys display   → 环境光 lux、屏幕亮度原始值、面板上限、HBM 状态
#   * display_brightness_config_<panel>.xml → 原始值→nit 档位表
#   * multimedia_display_brightness_config.xml → 自动亮度曲线（lux→nit）
# 不写任何文件、不改任何设置。
# ==========================================================================

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
ETC=/my_product/vendor/etc
[ -d "$ETC" ] || ETC=$MODDIR/my_product/vendor/etc

# ---------- 面板判定：AD296=P_3 / AA601=P_7 ----------
PANEL=P_3
case "$(cat /proc/cmdline 2>/dev/null)" in
  *AA601*) PANEL=P_7 ;;
  *AD296*) PANEL=P_3 ;;
esac
CFG=$ETC/display_brightness_config_$PANEL.xml
[ -f "$CFG" ] || { PANEL=P_3; CFG=$ETC/display_brightness_config_P_3.xml; }
CURVE=$ETC/multimedia_display_brightness_config.xml

# ---------- 原始值 -> nit（查档位表：<level>idx , raw, nit, ratio</level>）----------
nit_of() {
  awk -v v="$1" '
    match($0, /<level>[ ]*[0-9]+/) {
      split($0, a, ",")
      r = a[2] + 0; n = a[3] + 0
      if (r >= v) { printf "%.1f", n; exit }
    }
  ' "$CFG" 2>/dev/null
}

# ---------- 曲线：在给定 lux 处线性插值出目标 nit ----------
curve_nit() {
  awk -v L="$1" '
    match($0, /<lux>[0-9.]+,[0-9.]+<\/lux>/) {
      s = substr($0, RSTART + 5, RLENGTH - 11)
      split(s, p, ",")
      X[n] = p[1] + 0; Y[n] = p[2] + 0; n++
    }
    END {
      if (n == 0) { print "0"; exit }
      if (L <= X[0]) { printf "%.1f", Y[0]; exit }
      if (L >= X[n-1]) { printf "%.1f", Y[n-1]; exit }
      for (i = 1; i < n; i++) {
        if (L <= X[i]) {
          t = (L - X[i-1]) / (X[i] - X[i-1])
          printf "%.1f", Y[i-1] + t * (Y[i] - Y[i-1]); exit
        }
      }
      printf "%.1f", Y[n-1]
    }
  ' "$CURVE" 2>/dev/null
}

# ---------- 曲线原始点（供前端画图）----------
curve_points() {
  sed -n 's/.*<lux>\([0-9.]*\),\([0-9.]*\)<\/lux>.*/\1,\2/p' "$CURVE" 2>/dev/null
}

# ---------- 实时读数 ----------
dd=$(dumpsys display 2>/dev/null | grep -E "mLuxRecord =|Display State=|Display Brightness=|mHbmMode=|mMinBrightness=|mMaxBrightness=|mMaxPanelBrightness=")

lux=$(printf '%s\n' "$dd" | sed -n 's/.*LUX mStableValue = \([0-9.]*\).*/\1/p' | head -1)
raw=$(printf '%s\n' "$dd" | sed -n 's/^  Display Brightness=\([0-9.eE+-]*\).*/\1/p' | head -1)
scr=$(printf '%s\n' "$dd" | sed -n 's/^  Display State=\(.*\)$/\1/p' | head -1)
hbm=$(printf '%s\n' "$dd" | sed -n 's/^  mHbmMode=\(.*\)$/\1/p' | head -1)
bmin=$(printf '%s\n' "$dd" | sed -n 's/^ *mMinBrightness=\([0-9.]*\).*/\1/p' | tail -1)
bmax=$(printf '%s\n' "$dd" | sed -n 's/^ *mMaxBrightness=\([0-9.]*\).*/\1/p' | tail -1)
pmax=$(printf '%s\n' "$dd" | sed -n 's/^ *mMaxPanelBrightness=\([0-9.]*\).*/\1/p' | tail -1)
mode=$(settings get system screen_brightness_mode 2>/dev/null)

[ -n "$lux" ]  || lux=0
[ -n "$raw" ]  || raw=0
case "$raw" in -*|*[!0-9.]*) raw=0 ;; esac
[ -n "$scr" ]  || scr=unknown
[ -n "$hbm" ]  || hbm=unknown
[ -n "$bmin" ] || bmin=232
[ -n "$bmax" ] || bmax=4095
[ -n "$pmax" ] || pmax=4674
[ -n "$mode" ] || mode=1

nit=$(nit_of "$raw");        [ -n "$nit" ] || nit=0
cnit=$(curve_nit "$lux");    [ -n "$cnit" ] || cnit=0
pmaxnit=$(nit_of "$pmax");   [ -n "$pmaxnit" ] || pmaxnit=0

pct=$(awk -v r="$raw" -v a="$bmin" -v b="$bmax" 'BEGIN{d=b-a; if(d<=0)d=1; p=(r-a)*100/d; if(p<0)p=0; if(p>100)p=100; printf "%.1f", p}')

# 配置是否生效：/my_product/vendor/etc 是否为挂载点 + 模块版本
if mountpoint -q /my_product/vendor/etc 2>/dev/null; then eff=1; else eff=0; fi
modver=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -1)
appver=$(sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' "$ETC/display_brightness_app_list.xml" 2>/dev/null | head -1)

echo "update=$(getprop ro.build.version.ota 2>/dev/null | tr -d '[]' | cut -d, -f1)"
echo "modver=$modver"
echo "appver=$appver"
echo "panel=$PANEL"
echo "effective=$eff"
echo "screen=$scr"
echo "hbm=$hbm"
echo "mode=$mode"
echo "lux=$lux"
echo "raw=$raw"
echo "nit=$nit"
echo "curve_nit=$cnit"
echo "percent=$pct"
echo "bmin=$bmin"
echo "bmax=$bmax"
echo "pmax=$pmax"
echo "pmax_nit=$pmaxnit"
echo "curve_begin"
curve_points
echo "curve_end"
