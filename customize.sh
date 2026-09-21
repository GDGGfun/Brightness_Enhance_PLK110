SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=true
LATESTARTSERVICE=true

# v1.8.3：文件权限必须与原机一致（0644）。
# ApolloService 等显示 HAL 会拒绝解析全局可写的配置文件（0777），
# 导致激发亮度服务解析失败（GetApolloPanelNit error mParser）并引发相机/相册亮度异常。
set_perm_recursive $MODPATH 0 0 0755 0644
# SELinux 上下文对齐原机（vendor_configs_file），失败不阻断安装
chcon -R u:object_r:vendor_configs_file:s0 $MODPATH/my_product/vendor/etc 2>/dev/null || true

# ============ 第一行：署名 ============
ui_print "- 作者：酷安@雾织途_ | 修改：酷安@GDGGfun"
ui_print "- [OnePlus 15 自动亮度优化增强]"
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