#!/system/bin/sh
# 请不要硬编码 /magisk/modname/... ; 请使用 $MODDIR/...
# 这将使你的脚本更加兼容，即使Magisk在未来改变了它的挂载点
MODDIR=${0%/*}
# v1.8.3：挂载前把文件属性对齐原机（0644 + vendor_configs_file），
# 防止 ApolloService 等 HAL 因文件全局可写而拒绝解析
chmod 0644 $MODDIR/my_product/vendor/etc/*.xml 2>/dev/null
chmod 0644 $MODDIR/my_product/vendor/etc/EyeProtect/*.xml 2>/dev/null
chcon -R u:object_r:vendor_configs_file:s0 $MODDIR/my_product/vendor/etc/ 2>/dev/null || true
mount --bind $MODDIR/my_product/vendor/etc/ /my_product/vendor/etc/
#mount --bind $MODDIR/system_ext/etc/ /system_ext/etc/
#mount --bind $MODDIR/system_ext/oplus/ /system_ext/oplus/
# 这个脚本将以 post-fs-data 模式执行(系统启动前执行)
# 更多信息请访问 Magisk 主题
