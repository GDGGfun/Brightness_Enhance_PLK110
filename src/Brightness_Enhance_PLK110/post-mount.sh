#!/system/bin/sh
# ==========================================================================
# Brightness_Enhance_PLK110 —— 挂载兜底（v1.8.4 起）
#
# 设计原则：**依赖元模块挂载**
#   本模块不再在 post-fs-data 里自行 mount --bind。
#   配置目录 /my_product/vendor/etc 是 "promoted partition" 形态，
#   由 KernelSU 的元模块（本机为 Hybrid Mount，其 metainstall.sh 的
#   MANAGED_PARTITIONS 里含 my_product）在 metamount.sh 阶段统一挂载。
#
#   本脚本运行在 KSU 官方的 post-mount 阶段，**排在 metamount.sh 之后**，
#   所以不会与官方挂载抢同一个路径（v1.8.3 的 post-fs-data 绑定就是因此导致
#   元模块 overlay 挂载 EINVAL，并连累其它模块挂载失败）。
#
# 本脚本行为：
#   * 官方挂载已生效（路径已是挂载点）→ 立刻退出，什么都不做
#   * 官方挂载未生效 → 仅在此时补一次 bind mount 兜底
#   * 全程零写入：不 chmod、不 chcon、不写任何文件
#
# 注意：权限与 SELinux 上下文已在 **安装时**由 customize.sh 用官方
#       set_perm_recursive <dir> 0 0 0755 0644 u:object_r:vendor_configs_file:s0
#       一次性设好，运行时不再改动。
# ==========================================================================

MODDIR=${0%/*}

TARGET=/my_product/vendor/etc
SRC=$MODDIR/my_product/vendor/etc

# 源目录不存在则无事可做
[ -d "$SRC" ] || exit 0

# 目标路径必须是目录
[ -d "$TARGET" ] || exit 0

# 官方（元模块）已经挂好 → 不插手
if mountpoint -q "$TARGET" 2>/dev/null; then
  exit 0
fi

# 兜底：官方挂载缺失时才自行挂载。仅 mount，不写任何系统文件。
mount -o bind "$SRC" "$TARGET" 2>/dev/null

exit 0
