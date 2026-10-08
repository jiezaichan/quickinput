# 速填（QuickInput）

菜单栏文本片段工具：每条片段绑一个全局快捷键，按下即在当前光标处输入对应文本。纯 Swift + AppKit，不依赖 Xcode，只需要 Command Line Tools。

## 构建与安装

```bash
./sign-setup.sh       # 每台机器一次：生成本机签名证书（~/.quickinput-signing/）
./build.sh            # 编译并拼装 build/速填.app
./build.sh install    # 再装到 ~/Applications/速填.app 并启动；开机自启原来开着就保持开着
```

安装会顺带迁走 1.0 的旧标识 `com.jiezaichan.sutian`（旧 LaunchAgent、旧进程）。

**辅助功能授权**：系统按签名身份认人。跑过 `sign-setup.sh` 后用固定证书签名，授权一次以后重编译都不用再授权；没跑就退回 ad-hoc 签名，每次重装都要到「系统设置 → 隐私与安全性 → 辅助功能」删掉旧的「速填」重新勾选。菜单栏「辅助功能权限」一行显示当前状态；没授权时热键照常触发，但打不出字。证书删了重建（删 `~/.quickinput-signing/`）也要重新授权一次。

## 功能

- **片段快捷键**：每条片段可绑一个全局快捷键，按下在光标处输入
- **输入后回车**：片段勾上后，打完字隔 200ms 自动回车（命令类片段直接执行）
- **搜索面板**：默认 ⌃⌥⌘空格 呼出，打字筛选（名称命中优先、再匹配内容），↑↓ 选择、↩ 输入、esc 关闭；快捷键在设置窗口底部改，存在本机设置里，不随片段导入导出
- **导入导出**：菜单栏或设置窗口里「导入… / 导出…」，文件格式就是 `snippets.json` 本身。导入可选「合并」（id 相同覆盖、其余追加）或「替换全部」

## 数据

片段存在 `~/Library/Application Support/速填/snippets.json`（不进仓库），首次运行预置 `/compact` `/clear` `/resume` 三条（⌃⌥⌘ + C / V / R）。

## 代码结构

| 文件 | 内容 |
|---|---|
| `main.swift` | 入口与设计说明（为什么用 Carbon 热键 + CGEvent Unicode 输入） |
| `Store.swift` | 片段模型、读写 snippets.json、预置片段、合并 |
| `HotKeyCenter.swift` | Carbon `RegisterEventHotKey` 注册全局热键（含搜索面板快捷键），记录被占用的键 |
| `Typer.swift` | 等修饰键抬起后用 Unicode 键盘事件打字（不碰剪贴板、不被输入法截胡），可选补回车 |
| `SearchPanel.swift` | 搜索面板（nonactivatingPanel，不抢原 App 的焦点） |
| `Keys.swift` | 键码 ↔ 显示名、修饰键换算 |
| `HotKeyRecorder.swift` | 设置窗口里录快捷键的控件 |
| `SettingsWindow.swift` | 设置窗口 |
| `Transfer.swift` | 导入导出 |
| `LoginItem.swift` | 开机自启（写 LaunchAgent plist） |
| `AppDelegate.swift` | 菜单栏图标与菜单 |

改 Bundle ID 要同时改三处：`Resources/Info.plist`、`LoginItem.label`、`build.sh` 的 `LABEL`。
