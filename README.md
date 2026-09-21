# [OnePlus 15] 自动亮度优化增强

KernelSU 模块 —— 一加 15（PLK110 / OP60FFL1 / CPH2747）

作者：[@GDGGfun](https://github.com/GDGGfun) ｜ 参考模块作者：@天伞桜 @雾织途_ @官宣吖 @未晞月诶嘿 @呆又萌

当前发布版本：**v1.8.3**（已验证可正常开机使用）

---

## 功能

- 调整自动亮度曲线，抬高 10–100% 区间的整体亮度，解决原厂自动亮度偏暗、阅读困难
- 提高最大亮度至 2200nit，降低激发亮度阈值，提升阳光下可读性
- 自动亮度可自动触底到硬件 1nit（无光室内不再需要手动把亮度条拉到最低）
- 移除导航应用亮度特调
- 尽量保持温控等安全配置为原样，避免机身发烫或屏幕损坏

## 安装

1. 下载 [Release](https://github.com/GDGGfun/Brightness_Enhance_PLK110/releases/latest) 里的 zip
2. KernelSU 管理器 → 模块 → 安装本地模块
3. 重启

> 机型不匹配（非一加 15）时会在安装时弹出二次确认，按音量 + 强制安装、音量 − 取消。

## 卸载

KernelSU 管理器正常卸载即可。本模块**只做挂载覆盖，不写入任何系统文件**，卸载后不留任何持久改动。

## 设计原则

| 需求 | 实现方式 |
| --- | --- |
| 覆盖配置文件 | **bind mount**（重启即失效、模块禁用即还原） |
| 系统设置项 | `resetprop` / `setprop` |
| 开关状态 | KSU 官方 `ksud module config` |

- **不写入、不修改、不删除任何系统文件**（含 `/data/system`、`/my_product` 下的原文件）
- 无 `persist.*` 属性、无 `settings put`，重启后不留任何设置残留
- 兼容解锁与伪回锁：模块不生效时什么都不会发生
- 配置一律在原机文件基础上做最小修改，权限严格保持原机的 `0644`

## 更新

模块内置更新检查（`updateJson`），
在 KernelSU 管理器里可直接检测到新版本：<https://github.com/GDGGfun/Brightness_Enhance_PLK110/releases/latest>

## 目录结构

```text
Brightness_Enhance_PLK110/
├── module.prop            # 模块信息与更新链接
├── update.json            # 更新检查数据（指向最新 Release）
├── customize.sh           # 安装时：对齐文件权限与 SELinux 上下文
├── post-fs-data.sh        # 启动时：目录级 bind mount 覆盖配置
├── my_product/vendor/etc/ # 32 个亮度/显示配置文件（基于原机文件最小修改）
└── META-INF/
```

## 免责声明

修改显示 / 亮度 / 温控相关配置存在风险，请在了解后果的前提下使用；作者不承担任何责任。
