#!/system/bin/sh
# 供 WebUI 读取的实时状态，全程只读。
# 输出：每行一个 key=value；亮度曲线点包在 curve_begin / curve_end 之间（lux,nit）。

MODDIR=${0%/*}      # .../bin
MODDIR=${MODDIR%/*} # 模块根
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules/Brightness_Enhance_PLK110

ETC=/my_product/vendor/etc
[ -d "$ETC" ] || ETC=$MODDIR/my_product/vendor/etc

# 面板判定：cmdline 含 AA601 -> P_7，含 AD296 -> P_3
CMD=$(cat /proc/cmdline 2>/dev/null)
PANEL=P_3
case "$CMD" in
  *AA601*) PANEL=P_7 ;;
  *AD296*) PANEL=P_3 ;;
esac
CFG=$ETC/display_brightness_config_$PANEL.xml
[ -f "$CFG" ] || { PANEL=P_3; CFG=$ETC/display_brightness_config_P_3.xml; }
CURVE=$ETC/multimedia_display_brightness_config.xml
APP=$ETC/display_brightness_app_list.xml

# 面板型号：cmdline 的 dsi_display0 形如 qcom,mdss_dsi_panel_AD296_P_3_A0020_dsc_cmd
PANEL_NAME=$(printf '%s' "$CMD" | tr ' ' '\n' | sed -n 's/.*dsi_display0=qcom,mdss_dsi_panel_\([A-Za-z0-9_]*\)_A0020.*/\1/p' | head -1)
[ -n "$PANEL_NAME" ] || PANEL_NAME=unknown

# raw -> nit：取档位表中 raw 不超过 v 的最后一档。<level>idx , raw, nit, ratio</level>
nit_of() {
  awk -v v="$1" '
    match($0, /<level>/) {
      split($0, a, ",")
      r = a[2] + 0; n = a[3] + 0
      if (r <= v) last = n
    }
    END { printf "%.1f", last + 0 }
  ' "$CFG" 2>/dev/null
}

# 表末档 nit，即该面板配置的峰值
peak_nit() {
  awk '
    match($0, /<level>/) { split($0, a, ","); n = a[3] + 0 }
    END { printf "%.1f", n + 0 }
  ' "$CFG" 2>/dev/null
}

# 曲线插值：在给定 lux 处线性插值出目标 nit
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

# 曲线原始点列（供前端画图）
curve_points() {
  sed -n 's/.*<lux>\([0-9.]*\),\([0-9.]*\)<\/lux>.*/\1,\2/p' "$CURVE" 2>/dev/null
}

# 实时读数：只取需要的行，避免 dumpsys 全文开销
DD=$(dumpsys display 2>/dev/null | grep -E "mLuxRecord|Display State=|Display Brightness=|mHbmStatsState=|mMinBrightness=|mMaxBrightness=|mMaxPanelBrightness=|^ *mAutoBrightnessAdjustment=|mGlobalBrightnessLimitInfo|OplusFeatureUIR")

# 环境光必须锚定 mLuxRecord 行：CCT 记录行同样含 StableValue，只按 StableValue 会取到色温值
lux=$(printf '%s\n' "$DD" | sed -n 's/.*mLuxRecord.*StableValue = \([0-9.]*\).*/\1/p' | head -1)
raw=$(printf '%s\n' "$DD" | sed -n 's/^ *Display Brightness=\([0-9.eE+-]*\).*/\1/p' | head -1)
scr=$(printf '%s\n' "$DD" | sed -n 's/^ *Display State=\(.*\)$/\1/p' | head -1)
bmin=$(printf '%s\n' "$DD" | sed -n 's/^ *mMinBrightness=\([0-9.]*\).*/\1/p' | tail -1)
bmax=$(printf '%s\n' "$DD" | sed -n 's/^ *mMaxBrightness=\([0-9.]*\).*/\1/p' | tail -1)
pmax=$(printf '%s\n' "$DD" | sed -n 's/^ *mMaxPanelBrightness=\([0-9.]*\).*/\1/p' | tail -1)
mode=$(settings get system screen_brightness_mode 2>/dev/null)
adj=$(printf '%s\n' "$DD" | sed -n 's/^ *mAutoBrightnessAdjustment=\([0-9.]*\).*/\1/p' | head -1)

[ -n "$lux" ]  || lux=0
[ -n "$raw" ]  || raw=0
case "$raw" in -*|*[!0-9.]*) raw=0 ;; esac
[ -n "$scr" ]  || scr=unknown
[ -n "$bmin" ] || bmin=232
[ -n "$bmax" ] || bmax=4095
[ -n "$pmax" ] || pmax=4674
[ -n "$mode" ] || mode=1
[ -n "$adj" ]  || adj=0

nit=$(nit_of "$raw");        [ -n "$nit" ] || nit=0
cnit=$(curve_nit "$lux");    [ -n "$cnit" ] || cnit=0
peak=$(peak_nit);            [ -n "$peak" ] || peak=0

# 亮度条百分比：把原始值线性映射到 min~max
pct=$(awk -v r="$raw" -v a="$bmin" -v b="$bmax" 'BEGIN{d=b-a; if(d<=0)d=1; p=(r-a)*100/d; if(p<0)p=0; if(p>100)p=100; printf "%.1f", p}')

# 生效判定：挂载点上的面板配置与本模块内的同名文件一致即为生效；
# 机型不匹配时 customize.sh 会写入 skip_mount（WebUI 的模块开关也写它）
eff=0
SRCF=$MODDIR/my_product/vendor/etc/${CFG##*/}
if [ -f "$SRCF" ] && [ -f "$CFG" ]; then
  a=$(md5sum "$SRCF" 2>/dev/null | cut -d' ' -f1)
  b=$(md5sum "$CFG" 2>/dev/null | cut -d' ' -f1)
  [ -n "$a" ] && [ "$a" = "$b" ] && eff=1
fi
# 模块开关状态：skip_mount 存在 = 已禁用（元模块与 KSU 管理器都会跳过挂载本模块）
if [ -f "$MODDIR/skip_mount" ]; then sm=1; eff=0; else sm=0; fi

# 机型适配判定：条件必须与 customize.sh 的检测保持一致（device/model 三选一），改动要两处同步
dev=$(getprop ro.product.device 2>/dev/null)
mdl=$(getprop ro.product.model 2>/dev/null)
if [ "$dev" = "OP60FFL1" ] || [ "$mdl" = "PLK110" ] || [ "$mdl" = "CPH2747" ]; then
  match=1
else
  match=0
fi

# 系统版本（用户可见）：ro.build.display.id 形如 PLK110_16.0.3.503(CN01) -> 16.0.3.503（CN01）
sysver=$(getprop ro.build.display.id 2>/dev/null | sed -n 's/^[^_]*_//p' | sed 's/(/（/g; s/)/）/g')
[ -n "$sysver" ] || sysver=$(getprop ro.build.version.ota 2>/dev/null | tr -d '[]' | cut -d, -f1)

modver=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -1)
modname=$(sed -n 's/^name=//p' "$MODDIR/module.prop" 2>/dev/null | head -1)
appver=$(sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' "$APP" 2>/dev/null | head -1)

# 激发亮度阈值线 = 手动最高亮度：<brightness_table max="N"> 的 N 是手动可调上限，
# 它在档位表里对应的 nit 即该面板的手动峰值（PLK110 两面板均为 800nit）
nmax=$(sed -n 's/.*<brightness_table max="\([0-9]*\)".*/\1/p' "$CFG" 2>/dev/null | head -1)
[ -n "$nmax" ] || nmax=4095
hbm_th=$(nit_of "$nmax"); [ -n "$hbm_th" ] || hbm_th=0

# 激发亮度：原始亮度越过手动最高亮度（= 激发阈值）即视为已激发，与曲线图上的阈值线同口径。
# 不可用 mHbmMode —— 该字段恒为 off（它是配置项，不是状态）。
if awk -v r="$raw" -v n="$nmax" 'BEGIN{exit !(r > n)}' 2>/dev/null; then hbm=on; else hbm=off; fi
# 系统侧 HBM 统计状态，仅供参考
hbm_sys=$(printf '%s\n' "$DD" | sed -n 's/.*mHbmStatsState=\([A-Z_]*\).*/\1/p' | head -1)

# 全局亮度门限（应用级限制），仅供参考
gth=$(sed -n 's/.*<global_brightness_limit[^>]*nit="\([0-9]*\)".*/\1/p' "$APP" 2>/dev/null | head -1)
[ -n "$gth" ] || gth=0

# 运行时实际生效的两个亮度门限（display 服务施加的值，配置改了要看这里才作数）
# 这两行原文很长（内嵌 app 列表），用 grep -o 提取，sed 整行替换会超长失败
# 注：UIR 的写法是 "mLimitNit = 1600"，等号两侧带空格
glim=$(printf '%s\n' "$DD" | grep -o 'GlobalLimit=[0-9][0-9]*' | head -1 | cut -d= -f2)
ulim=$(printf '%s\n' "$DD" | grep -o 'mLimitNit *= *[0-9][0-9]*' | head -1 | grep -o '[0-9][0-9]*$')
[ -n "$glim" ] || glim=0
[ -n "$ulim" ] || ulim=0

echo "update=$(getprop ro.build.version.ota 2>/dev/null | tr -d '[]' | cut -d, -f1)"
echo "sysver=$sysver"
echo "model=$mdl"
echo "device_match=$match"
echo "modver=$modver"
echo "modname=$modname"
echo "appver=$appver"
echo "panel=$PANEL"
echo "panel_name=$PANEL_NAME"
echo "effective=$eff"
echo "skip_mount=$sm"
echo "screen=$scr"
echo "hbm=$hbm"
echo "hbm_sys=$hbm_sys"
echo "mode=$mode"
echo "lux=$lux"
echo "raw=$raw"
echo "nit=$nit"
echo "curve_nit=$cnit"
echo "percent=$pct"
echo "bmin=$bmin"
echo "bmax=$bmax"
echo "pmax=$pmax"
echo "peak_nit=$peak"
echo "hbm_threshold=$hbm_th"
echo "global_nit=$gth"
echo "global_limit=$glim"
echo "uir_limit=$ulim"
echo "auto_adj=$adj"
echo "curve_begin"
curve_points
echo "curve_end"
