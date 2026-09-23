SKIPMOUNT=true   # 挂载禁用：详见文件末尾「禁用模块自带挂载」一节
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=false

# ==========================================================================
# 文件权限与 SELinux 上下文 —— 安装时用官方函数一次到位
#   * 权限必须与原机一致（0644）：ApolloService 等显示 HAL 会拒绝解析全局可写
#     的配置文件（0777），导致 GetApolloPanelNit error mParser 并引发相机/相册亮度异常。


set_perm_recursive $MODPATH 0 0 0755 0644

# ============ 第一行：署名 ============
ui_print "*********************************************"
ui_print "- 作者：酷安@GDGGfun"
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
    ui_print "!!!                                       !!!"
    ui_print "!!!  [警告] 模块不适配当前机型！               !!!"
    ui_print "!!!  当前机型: $model / $device"
    ui_print "!!!  本模块仅适配一加15 (PLK110)             !!!"
    ui_print "!!!                                       !!!"
    ui_print "!!!  [注意] 安装后模块配置不会生效，            !!!"
    ui_print "!!!   但仍可以使用webui部分功能               !!!"
    ui_print "!!!                                       !!!"
    ui_print "#############################################"
    ui_print ""

    # ---------- 禁用模块自带挂载，同时设置为让元模块跳过挂载 ----------
    SKIPMOUNT=true
    touch "$MODPATH/skip_mount"     #禁用挂载标识
    touch "$MODPATH/skip_mountify"  #禁用挂载标识
    rm -f "$MODPATH/post-mount.sh"  #删除自挂载脚本
fi

sleep 0.5
print_line