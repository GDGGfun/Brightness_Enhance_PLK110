# [OnePlus 15] 自动亮度优化增强

KernelSU 模块 —— 一加 15（PLK110 / OP60FFL1 / CPH2747）

作者：[@GDGGfun](https://github.com/GDGGfun) ｜ 参考模块作者：@天伞桜 @雾织途_ @官宣吖 @未晞月诶嘿 @呆又萌

当前版本：**v1.8.5**

---

## 功能

- 调整自动亮度曲线，抬高 10–100% 区间的整体亮度，解决原厂自动亮度偏暗、阅读困难
- 提高最大亮度至 2200nit，降低激发亮度阈值，提升阳光下可读性
- 自动亮度可自动触底到硬件 1nit（无光室内不再需要手动把亮度条拉到最低）
- **移除导航应用亮度特调**：原机把地图类 App 放进「进应用降亮度」method
  （≥800nit 削 37.5%、≥2000nit 削 60%），使它们永远够不到激发亮度门槛；现已移出该 method
  并加入 `global_brightness_limit` 豁免名单
- 尽量保持温控等安全配置为原样，避免机身发烫或屏幕损坏

## WebUI

在 KernelSU 管理器里点击本模块的 **WebUI 快捷入口**打开（模块内 `webroot/`）：

- **实时环境光**：当前传感器 lux（对数刻度条）
- **实时屏幕亮度**：当前 nit、系统亮度原始值、亮度条百分比
- **自动亮度曲线**：完整 lux→nit 曲线，并标出**当前工作点**
  （红点＝实际亮度、绿点＝曲线目标），附 800nit 激发门槛参考线
- 激发亮度状态 / 屏幕状态 / 亮度模式 / 面板上限 / app_list 版本
- 2 秒自动轮询；数据来自模块内 `bin/status.sh`（**只读**，不写任何文件）

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
| 覆盖配置文件 | **依赖 KernelSU 元模块挂载**（`/my_product/vendor/etc` 以 promoted-partition 形态提供，由元模块的 `metamount.sh` 统一挂载；本机元模块 Hybrid Mount 的托管分区表里含 `my_product`） |
| 兜底 | `post-mount.sh`（KSU 官方阶段，排在 `metamount` 之后）：已是挂载点则什么都不做，仅在官方挂载缺失时补一次 bind mount |
| 权限 / SELinux 上下文 | 安装时用官方 `set_perm_recursive <dir> 0 0 0755 0644 u:object_r:vendor_configs_file:s0` 一次设好；**启动脚本零写入、不做 chmod/chcon** |
| 系统设置项 | 不涉及（本模块不改任何 prop） |

- **不写入、不修改、不删除任何系统文件**（含 `/data/system`、`/my_product` 下的原文件）
- **没有 `post-fs-data.sh`**：不在阻塞的启动早期做任何事，也不与元模块抢挂载
- 无 `persist.*` 属性、无 `settings put`，重启后不留任何设置残留
- 兼容解锁与伪回锁：模块不生效时什么都不会发生
- 配置一律在原机文件基础上做最小修改（本版除导航特调外，只改了
  `maxLux`、`global_brightness_limit nit`、`dark_env_*` 三处），权限严格保持原机的 `0644`

## 工程结构（Kam 工程）

```
Brightness_Enhance_PLK110/
├── kam.toml                                # Kam 工程配置（模块元数据 + 构建选项）
├── update.json                             # 更新检查（指向最新 Release）
├── README.md
└── src/Brightness_Enhance_PLK110/          # 模块内容
    ├── customize.sh                        # 安装时对齐权限与 SELinux 上下文
    ├── post-mount.sh                       # 挂载兜底（官方 post-mount 阶段）
    ├── module.prop
    ├── bin/status.sh                       # WebUI 数据源（只读）
    ├── webroot/                            # WebUI（index.html / style.css / app.js）
    ├── my_product/vendor/etc/              # 32 个亮度/显示配置（基于原机最小修改）
    └── META-INF/
```

构建：`kam validate && kam export && kam build --release --sign`

## 更新

模块内置更新检查（`updateJson`），在 KernelSU 管理器里可直接检测新版本：
<https://github.com/GDGGfun/Brightness_Enhance_PLK110/releases/latest>

## 免责声明

修改显示 / 亮度 / 温控相关配置存在风险，请在了解后果的前提下使用；作者不承担任何责任。
