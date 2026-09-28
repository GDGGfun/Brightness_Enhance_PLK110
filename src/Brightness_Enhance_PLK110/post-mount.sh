#!/system/bin/sh
# 逐文件挂载兜底：模块只挂 FILES 里那几个定制配置，其余原机文件一律不动。
#
# 目前只覆盖 my_product/vendor/etc（自动亮度曲线、面板档位表、app 名单、UIR nit 上限）。
# 刻意**不覆盖** system_ext/etc 的温控 nit 表：那是安全配置，按用户 2026-09-28 定调保持原机值。
#
# 为什么逐文件而不是整目录 bind：
#   元模块 Hybrid Mount 的 overlay 以模块目录为高优先级 lowerdir，模块里没有的文件会回落到
#   原机文件（只有带 .replace 标记的目录才 opaque）。逐文件挂载既不会顶掉未改动件，也不需要
#   模块做完整镜像；反过来整目录 bind 会让模块里没有的文件连带消失。
#
# 兜底口径（条件兜底，不是无条件挂）：
#   本脚本跑在 KSU 官方 post-mount 阶段（排在元模块 metamount.sh 之后），
#   逐个比 md5：当前生效文件与模块文件一致 ⇒ 元模块已提供正确内容，不挂；
#   不一致 ⇒ 元模块没覆盖到，才补一次 bind。零写入（不 chmod / chcon，也不创建文件）。
#
# 限制：bind 要求目标文件已存在，故本脚本只能覆盖原机已有文件；
#   模块将来新增（原机没有）的文件只能依赖元模块 overlay，本脚本不创建文件。

MODDIR=${0%/*}

# 机型不匹配时 customize.sh 会写入 skip_mount，此时一律不挂载
[ -e "$MODDIR/skip_mount" ] && exit 0

# 模块携带的定制配置：写成"模块相对路径"，同时就是设备绝对路径去掉前导 /。
# 必须与 .开发/tools/build_release.py 的 CONFIG_DIRS 白名单完全一致（构建期逐项校验）
FILES="my_product/vendor/etc/display_brightness_app_list.xml
my_product/vendor/etc/display_brightness_config_P_3.xml
my_product/vendor/etc/display_brightness_config_P_7.xml
my_product/vendor/etc/multimedia_display_brightness_config.xml
my_product/vendor/etc/multimedia_display_uir_config.xml"

for rel in $FILES; do
  src=$MODDIR/$rel
  tgt=/$rel
  [ -f "$src" ] || continue
  [ -f "$tgt" ] || continue
  a=$(md5sum "$tgt" 2>/dev/null | cut -d' ' -f1)
  b=$(md5sum "$src" 2>/dev/null | cut -d' ' -f1)
  [ -n "$a" ] && [ "$a" = "$b" ] && continue
  mount -o bind "$src" "$tgt" 2>/dev/null
done

exit 0
