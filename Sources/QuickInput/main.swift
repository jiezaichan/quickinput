// 速填 —— 菜单栏文本片段工具
//
// 每条片段绑一个全局快捷键，按下即在当前光标处输入对应文本。
// 关键设计：热键由本进程用 Carbon RegisterEventHotKey 注册，按键事件也由本进程
// 用 CGEvent 发出，所以 TCC 判定的「责任进程」始终是本 App 自己 —— 在辅助功能
// 列表里授权一次即永久有效，不会出现经由快捷指令/XPC 转发时的权限漂移。
// 输入走 Unicode 键盘事件而非剪贴板，因此不覆盖剪贴板、也不被中文输入法截胡。

import Cocoa

// build.sh install 迁移旧 LaunchAgent 自启时带此参数启动
if CommandLine.arguments.contains("--register-login-item") { LoginItem.set(true) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
