#!/system/bin/sh
# 挂载兜底：元模块已把 /my_product/vendor/etc 挂好时不动作；
# 官方挂载缺失时才补一次 bind mount。零写入（不 chmod / chcon / 写文件）。

MODDIR=${0%/*}
TARGET=/my_product/vendor/etc
SRC=$MODDIR/my_product/vendor/etc

[ -d "$SRC" ] || exit 0
[ -d "$TARGET" ] || exit 0

# 元模块已挂载，不插手
mountpoint -q "$TARGET" 2>/dev/null && exit 0

# 兜底挂载
mount -o bind "$SRC" "$TARGET" 2>/dev/null

exit 0
