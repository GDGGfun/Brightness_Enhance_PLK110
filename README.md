# [OnePlus 15] 自动亮度优化增强

KernelSU / Magisk 模块 一加 15（PLK110）

作者：[@GDGGfun](https://github.com/GDGGfun)

---
## 装前必看

- **KSU必须安装元模块** 推荐Hybrid Mount
- **支持**： 越狱、免解、伪回锁
- **适配机型**：一加 15（PLK110）
- **安装方法**：安装元模块后（ksu），在管理器中选择模块压缩包安装


## 模块功能简介

- **亮度曲线**：抬高 10–100% 区间的整体亮度，解决原厂自动亮度偏暗、阅读困难的问题
- **激发亮度**：峰值提高至2200nit，降低激发亮度触发阈值，提升阳光下可读性
- **自动1nit**：自动亮度条可自动触底，无需要手动拉亮度条
- **亮度特调**：把导航类App移出降亮度method，移入`global_brightness_limit`白名单
- **安全配置**：保留温控避免机身发烫或屏幕损坏，现在手机很贵的

模块自带 WebUI ，在 KernelSU 管理器可快捷打开：


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


## 反馈渠道

如遇问题、建议，或想交流亮度调校经验，欢迎加入 QQ 交流群：
**695176727**

问题追踪也可以提 Issue：
<https://github.com/GDGGfun/Brightness_Enhance_PLK110/issues>

## 致谢

参考了以下作者的模块，特此致谢：

酷安：**@天伞桜** ｜ **@雾织途_** ｜ **@官宣吖** ｜ **@未晞月诶嘿** ｜ **@呆又萌**

以及 [KernelSU](https://github.com/tiann/KernelSU)、
[Kam](https://github.com/MemDeco-WG/Kam) 等开源项目。

## 免责声明

修改显示 / 亮度 / 温控相关配置存在风险，请在了解后果的前提下使用；
作者不承担任何责任。
