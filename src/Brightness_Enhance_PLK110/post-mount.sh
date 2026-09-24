#!/system/bin/sh
# 逐文件挂载兜底：模块只提供 FILES 里那几个定制配置，其余原机配置一律不动。
#
# 为什么不再整目录 bind：
#   元模块 Hybrid Mount 的 overlay（真机 mountinfo 370，lowerdir = 模块目录 : /my_product/vendor）
#   以模块目录为高优先级层，而模块目录不是 opaque（只有带 .replace 标记才 opaque），
#   所以模块没有的文件会自动回落到原机文件 —— 删掉未改动件后依然完整。
#   反过来，整目录 bind 会把 /my_product/vendor/etc 整个换成模块目录，模块里没有的文件
#   连带消失，等于把 27 个未改动件钉死在旧版基线（新系统升级过的同名文件会被顶掉）。
#
# 兜底口径（条件兜底，不是无条件挂）：
#   本脚本跑在 KSU 官方 post-mount 阶段（排在元模块 metamount.sh 之后），
#   逐个比 md5：当前生效文件与模块文件一致 ⇒ 元模块已提供正确内容，不挂；
#   不一致 ⇒ 元模块缺失/没覆盖到，才补一次 bind。零写入（不 chmod / chcon，也不创建文件）。
#
# 限制：bind 要求目标文件已存在，故本脚本只能覆盖原机已有文件；
#   模块将来新增（原机没有）的文件只能依赖元模块 overlay，本脚本不创建文件。

MODDIR=${0%/*}
SRC=$MODDIR/my_product/vendor/etc
TARGET=/my_product/vendor/etc

# 机型不匹配时 customize.sh 会写入 skip_mount，此时一律不挂载
[ -e "$MODDIR/skip_mount" ] && exit 0
[ -d "$SRC" ] || exit 0
[ -d "$TARGET" ] || exit 0

# 模块提供的定制配置：必须与 .开发/tools/build_release.py 的 ALLOW_CUSTOMIZED 完全一致
# （构建期会逐项校验，不一致直接中止构建）
FILES="display_brightness_app_list.xml
display_brightness_config_P_3.xml
display_brightness_config_P_7.xml
multimedia_display_brightness_config.xml
multimedia_display_uir_config.xml"

for f in $FILES; do
  src=$SRC/$f
  tgt=$TARGET/$f
  [ -f "$src" ] || continue
  [ -f "$tgt" ] || continue
  a=$(md5sum "$tgt" 2>/dev/null | cut -d' ' -f1)
  b=$(md5sum "$src" 2>/dev/null | cut -d' ' -f1)
  [ -n "$a" ] && [ "$a" = "$b" ] && continue
  mount -o bind "$src" "$tgt" 2>/dev/null
done

exit 0
