# 挂载策略：模块顶层是 promoted 分区 my_product/（没有 system/），配置全部交给元模块
# （Hybrid Mount）挂载，模块自身永不参与自挂载。
#
# SKIPMOUNT 必须为 false —— 反直觉，但依据明确：
#   元模块的判定是 mountable = has_mount_files && !disabled && !skip_mount
#   （meta-hybrid_mount src/scanner.rs），即 skip_mount 一旦存在，元模块就会拒绝挂载本模块；
#   而 Magisk 系安装器会按 SKIPMOUNT 自动生成 skip_mount，那等于自断挂载。
#   注：KernelSU 的安装器只在 install.sh 老式模块分支处理 SKIPMOUNT（ksud/src/installer.sh:396），
#   本模块走 customize.sh 分支，故该变量在 KSU 下本就不起作用。
SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=false

# 权限：目录 0755 / 文件 0644，须与原机一致。
# 0777 会被 ApolloService 等显示 HAL 拒绝解析（GetApolloPanelNit error mParser），引发相机、相册亮度异常
set_perm_recursive $MODPATH 0 0 0755 0644

# 署名
ui_print "*********************************************"
ui_print "- 作者：酷安@GDGGfun"
ui_print "- [OnePlus 15 自动亮度优化增强]"
ui_print "*********************************************"

# 机型检测：一加15（model=PLK110/CPH2747，device=OP60FFL1）
device=$(getprop ro.product.device)
model=$(getprop ro.product.model)

if [ "$device" = "OP60FFL1" ] || [ "$model" = "PLK110" ] || [ "$model" = "CPH2747" ]; then
    ui_print "- 检测到一加15 (model=$model)"
    ui_print "- 机型匹配，自动安装，无需确认"
else
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

    # 机型不匹配：禁止挂载，只保留 WebUI 功能。
    # 真正让元模块跳过的是 skip_mount —— 元模块不认 skip_mountify（那是 Mountify 的标识）。
    # 同时移除 post-mount 兜底脚本，否则它会把配置重新 bind 上去。
    SKIPMOUNT=true
    touch "$MODPATH/skip_mount"
    rm -f "$MODPATH/post-mount.sh"
fi
