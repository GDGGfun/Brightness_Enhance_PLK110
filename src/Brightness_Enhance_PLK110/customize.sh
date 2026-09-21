SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=false

# ==========================================================================
# 文件权限与 SELinux 上下文 —— 安装时用官方函数一次到位
#
# 这是"权限匹配"的唯一权威来源：
#   * 权限必须与原机一致（0644）：ApolloService 等显示 HAL 会拒绝解析全局可写
#     的配置文件（0777），导致 GetApolloPanelNit error mParser 并引发相机/相册亮度异常。
#   * SELinux 上下文必须对齐原机 vendor_configs_file，否则框架读不到。
#
# 不再在启动脚本里 chmod/chcon —— 启动脚本零写入。
# （平台 file_contexts 把 /data/adb 定为 adb_data_file，开机的 restorecon 会覆盖
#   这里的标签；因此标签的最终生效由挂载方按挂载时的源文件属性决定，见
#   experiences/挂载方式改造_依赖元模块挂载.md）
# ==========================================================================

# 1) 模块脚本与自有目录（**故意不碰 webroot**）
#    KSU 官方 WebUI 文档明确：安装时 KSU 会自动设置 webroot 目录的权限与 SELinux context，
#    「如果您不知道自己在做什么，请不要自行设置该目录的权限！」
for d in bin my_product; do
  [ -d "$MODPATH/$d" ] && set_perm_recursive $MODPATH/$d 0 0 0755 0755
done
[ -f "$MODPATH/post-mount.sh" ] && set_perm $MODPATH/post-mount.sh 0 0 0755
[ -f "$MODPATH/customize.sh" ]  && set_perm $MODPATH/customize.sh  0 0 0755
[ -f "$MODPATH/module.prop" ]   && set_perm $MODPATH/module.prop   0 0 0644

# 2) 配置目录：权限严格对齐原机 0644，SELinux 上下文对齐原机 vendor_configs_file
set_perm_recursive $MODPATH/my_product/vendor/etc 0 0 0755 0644 u:object_r:vendor_configs_file:s0

# ============ 第一行：署名 ============
ui_print "- 作者：酷安@GDGGfun"
ui_print "- [OnePlus 15 自动亮度优化增强] v1.8.5"
ui_print "- 挂载：依赖 KernelSU 元模块（不在 post-fs-data 自行 mount --bind）"
ui_print "- 权限与 SELinux 上下文：安装时用官方 set_perm_recursive 一次设好"
ui_print "- 新增 WebUI：实时环境光 / 屏幕亮度 / 曲线工作点"
ui_print "- 已去除导航类应用亮度特调"
ui_print "*********************************************"

# ============ 机型检测 ============
device=$(getprop ro.product.device)
model=$(getprop ro.product.model)

if [ "$device" = "OP60FFL1" ] || [ "$model" = "PLK110" ] || [ "$model" = "CPH2747" ]; then
    ui_print "- 检测到一加15 (model=$model)"
    ui_print "- 机型匹配，自动安装，无需确认"
else
    # ============ 非一加15：醒目纯文本警告 ============
    ui_print "#############################################"
    ui_print "!!!                                      !!!"
    ui_print "!!!  [警告] 当前机型不是一加15！          !!!"
    ui_print "!!!  当前机型: $model / $device"
    ui_print "!!!                                      !!!"
    ui_print "!!!  本模块专为一加15 (PLK110/CPH2747)   !!!"
    ui_print "!!!  适配，强制安装可能导致屏幕亮度异常、    !!!"
    ui_print "!!!  显示花屏，甚至无法开机！          !!!"
    ui_print "!!!                                      !!!"
    ui_print "#############################################"
    ui_print ""

    # ---------- 二次确认函数 ----------
    # 等待音量键按下事件，设置全局变量 VOLUME_KEY 为 "up" 或 "down"
    # 返回 0 表示成功，返回 1 表示超时
    VOLUME_KEY=""
    wait_for_volume_key() {
        local timeout=10
        local start=$(date +%s)
        while true; do
            local now=$(date +%s)
            if [ $((now - start)) -ge $timeout ]; then
                return 1
            fi
            event=$(getevent -l -c 1 2>/dev/null)
            if [ -n "$event" ]; then
                if echo "$event" | grep -q "KEY_VOLUMEUP.*DOWN"; then
                    VOLUME_KEY="up"
                    return 0
                elif echo "$event" | grep -q "KEY_VOLUMEDOWN.*DOWN"; then
                    VOLUME_KEY="down"
                    return 0
                fi
            fi
            sleep 0.1
        done
    }

    # ---------- 第一次确认 ----------
    ui_print "- 是否确认安装："
    ui_print "- 按下音量+ ：确认强制安装"
    ui_print "- 音量- ：取消安装"
    ui_print ""
    ui_print "- 请选择音量键..."
    wait_for_volume_key
    if [ $? -ne 0 ]; then
        ui_print "- 超时，已取消安装"
        exit 1
    fi
    if [ "$VOLUME_KEY" = "down" ]; then
        ui_print "- 已取消安装"
        exit 1
    fi

    # ---------- 第二次确认 ----------
    ui_print "- 您在在未验证的机型上安装！"
    ui_print ""
    ui_print "- 二次确认："
    ui_print "- 再次按下音量+ ：确认强制安装"
    ui_print "- 音量- ：取消安装"
    ui_print ""
    ui_print "- 请按音量键..."
    wait_for_volume_key
    if [ $? -ne 0 ]; then
        ui_print "- 超时，已取消安装"
        exit 1
    fi
    if [ "$VOLUME_KEY" = "up" ]; then
        ui_print "- 已确认，强制安装中..."
    else
        ui_print "- 已取消安装"
        exit 1
    fi
fi

sleep 0.5
print_line