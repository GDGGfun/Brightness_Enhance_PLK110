#!/system/bin/sh
# 模块开关（WebUI 反馈页调用）：用 skip_mount 控制"下次开机是否挂载配置"。
#   off    = 禁用模块：创建 skip_mount，重启后不再挂载配置（元模块 Hybrid Mount 与
#            KSU 管理器都认这个文件；本模块的 post-mount.sh 见到它也一律不挂载）
#   on     = 启用模块：删除 skip_mount，重启后恢复挂载
#   status = 输出 SKIP_MOUNT=0|1
#   mode   = 输出 LATE_LOAD/MODE，供人工核对重启方式判定
#   reboot = 按设备状态选择重启方式：
#              越狱/伪回锁（KSU late_load=true）⇒ 只用 ksud soft-reboot 软重启
#                （普通重启会掉 root；软重启会重跑 post-fs-data，skip_mount 同样生效）
#              普通设备（late_load=false）  ⇒ svc power reboot，失败退 reboot
#              判定不出来                    ⇒ 只输出 RESULT=PROMPT，不执行任何重启
#
# 全程只写模块自身目录里的 skip_mount：不碰系统文件、不改任何属性、不写 /data 其它位置。

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules/Brightness_Enhance_PLK110
SM=$MODDIR/skip_mount
KSUD=/data/adb/ksu/bin/ksud

# 取 KSU 的 late_load 标志（越狱模式判定，与管理器 Natives.isLateLoadMode 同口径）；
# 取不到就输出空串，由调用方决定"只提示不重启"。
late_load() {
  [ -x "$KSUD" ] || KSUD=$(command -v ksud 2>/dev/null)
  [ -n "$KSUD" ] && [ -x "$KSUD" ] || return 0
  "$KSUD" debug info 2>/dev/null | sed -n 's/^late_load: *//p' | head -1
}

case "$1" in
  off)
    touch "$SM" 2>/dev/null
    if [ -f "$SM" ]; then
      echo "RESULT=OK|off"
    else
      echo "RESULT=ERR|无法创建 $SM（模块目录不可写？）"
      exit 1
    fi
    ;;
  on)
    rm -f "$SM" 2>/dev/null
    if [ -f "$SM" ]; then
      echo "RESULT=ERR|无法删除 $SM"
      exit 1
    fi
    echo "RESULT=OK|on"
    ;;
  status)
    if [ -f "$SM" ]; then echo "SKIP_MOUNT=1"; else echo "SKIP_MOUNT=0"; fi
    ;;
  mode)
    ll=$(late_load)
    case "$ll" in
      true)  echo "LATE_LOAD=true";  echo "MODE=soft" ;;
      false) echo "LATE_LOAD=false"; echo "MODE=normal" ;;
      *)     echo "LATE_LOAD=unknown"; echo "MODE=unknown" ;;
    esac
    ;;
  reboot)
    ll=$(late_load)
    if [ -z "$ll" ]; then
      echo "RESULT=PROMPT|无法确认 KernelSU 运行状态（读不到 late_load），请手动重启手机使其生效"
      exit 0
    fi
    if [ "$ll" = "true" ]; then
      "$KSUD" soft-reboot >/dev/null 2>&1
      echo "RESULT=OK|soft"
    else
      /system/bin/svc power reboot >/dev/null 2>&1
      sleep 3
      /system/bin/reboot >/dev/null 2>&1
      sleep 3
      echo "RESULT=ERR|重启命令未生效，请手动重启"
      exit 1
    fi
    ;;
  *)
    echo "用法: modctl.sh status|mode|on|off|reboot"
    exit 2
    ;;
esac

exit 0
