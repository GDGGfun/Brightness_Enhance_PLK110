# [OnePlus 15] 自动亮度优化增强

KernelSU / Magisk 模块 —— 一加 15（PLK110 / OP60FFL1 / CPH2747）

作者：[@GDGGfun](https://github.com/GDGGfun)

---

## 模块功能简介

- **调整自动亮度曲线**：抬高 10–100% 区间的整体亮度，解决原厂自动亮度偏暗、阅读困难
- **提高最大亮度至 2200nit**，降低激发亮度触发阈值，提升阳光下可读性
- **自动亮度可自动触底到硬件 1nit**：无光室内不再需要手动把亮度条拉到最低
- **移除导航应用亮度特调**：原机把地图类 App 放进「进应用降亮度」的 method
  （≥800nit 削 37.5%、≥2000nit 削 60%），使它们永远够不到激发亮度门槛；
  现已移出该 method 并加入 `global_brightness_limit` 豁免名单
- **尽量保持温控等安全配置为原样**，避免机身发烫或屏幕损坏

模块自带 **WebUI**，在 KernelSU 管理器里点击本模块的「WebUI 快捷入口」即可打开：

- **实时环境光**：当前传感器 lux（对数刻度条）
- **实时屏幕亮度**：当前 nit、系统亮度原始值、亮度条百分比
- **自动亮度曲线**：完整 lux→nit 曲线，并标出当前工作点
  （红点＝实际亮度、绿点＝曲线目标），附 800nit 激发门槛参考线
- 激发亮度状态 / 屏幕状态 / 亮度模式 / 面板上限 / app_list 版本
- 数据来自模块内 `bin/status.sh`，**只读**，不写任何文件

## 模块依赖

- **KernelSU**（含 KernelSU Next 及基于 KernelSU 的分支）或 **Magisk**
- **设备**：一加 15（PLK110 / OP60FFL1 / CPH2747）
- 覆盖配置文件依赖 KernelSU **元模块挂载机制**（元模块需托管 `my_product` 分区；
  未启用元模块时模块内有兜底逻辑）

## 安装教程

1. 从 [Releases](https://github.com/GDGGfun/Brightness_Enhance_PLK110/releases/latest)
   下载最新的 zip 包
2. 打开 KernelSU 管理器 → **模块** → **安装本地模块**，选择该 zip
3. **重启手机**生效
4. 重启后可在管理器里点击本模块的 **WebUI 快捷入口**，查看实时亮度与曲线

> **国内下载加速**：若 GitHub 下载缓慢，可在**安装包的下载链接**前拼接
> `https://gh-proxy.org/` 走加速通道，例如
> `https://gh-proxy.org/https://github.com/GDGGfun/Brightness_Enhance_PLK110/releases/download/...`
> （只对文件下载链接有效；`/releases/latest` 这类**网页链接不适用**——代理对网页返回 403。）
> 模块内置的更新检查（KernelSU 管理器里点「更新」）已默认走该加速通道，无需手动操作。

> **机型不匹配提示**：非一加 15 刷入时会在安装阶段弹出二次确认，
> 按 **音量 +** 强制安装、按 **音量 −** 取消。

### 卸载

KernelSU 管理器正常卸载即可。本模块**只做挂载覆盖，不写入任何系统文件**，
卸载后不留任何持久改动。

## 反馈渠道

遇到问题、有建议，或想交流亮度调校经验，欢迎加入 QQ 交流群：

> **QQ 群号：695176727**

问题追踪也可以提 Issue：
<https://github.com/GDGGfun/Brightness_Enhance_PLK110/issues>

## 致谢

参考了以下作者的模块实现，特此致谢：

**@天伞桜** ｜ **@雾织途_** ｜ **@官宣吖** ｜ **@未晞月诶嘿** ｜ **@呆又萌**

以及 [KernelSU](https://github.com/tiann/KernelSU)、
[Kam](https://github.com/MemDeco-WG/Kam) 等开源项目。

## 安全设计

- **不写入、不修改、不删除任何系统文件**（含 `/data/system`、`/my_product` 下的原文件）
- 配置覆盖一律走**挂载**；无 `persist.*` 属性、无 `settings put`，重启后不留任何设置残留
- 启动脚本**零写入**，权限与 SELinux 上下文在安装阶段一次设好
- 兼容解锁与伪回锁：模块不生效时什么都不会发生
- 配置一律在**原机文件**基础上做最小修改，权限严格保持原机的 `0644`

## 更新日志

各版本的详细更新内容见 [CHANGELOG.md](CHANGELOG.md)。

> 该文件也是模块更新检查读取的更新说明（KernelSU 管理器点「更新」时会以内嵌
> Markdown 形式展示），因此只写具体更新内容。

## 免责声明

修改显示 / 亮度 / 温控相关配置存在风险，请在了解后果的前提下使用；
作者不承担任何责任。
