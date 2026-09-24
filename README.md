# SSH Monitor

通过现有 SSH 配置监控 Linux 服务器的 macOS 菜单栏应用。状态栏只显示 SSH 状态和最高 GPU 利用率；点击后可查看 CPU、系统内存已用/总量，以及每张 NVIDIA GPU 的利用率、显存已用/总量和温度。菜单栏、弹窗标题和悬停提示不展示主机别名。没有 NVIDIA GPU 时，CPU、内存和 SSH 状态仍可使用。

## 如何使用

1. 在 Mac 的 `~/.ssh/config` 中配置一个可免交互登录的别名，例如：

   ```sshconfig
   Host my-server
     HostName <your-hostname-or-ip>
     User <your-user>
     IdentityFile ~/.ssh/id_ed25519
   ```

   先运行 `ssh -o BatchMode=yes my-server true`，确认密钥登录和主机密钥验证均已配置好。这里的 `my-server` 仅是示例，仓库没有预设真实服务器。

2. 在 macOS 14 或更新版本安装 Swift Command Line Tools 后，克隆本仓库并运行：

   ```bash
   ./scripts/swift-tool.sh test
   ./scripts/build.sh --install
   ```

3. 点击菜单栏中的 **SSH Monitor**，在「设置」中填写自己的 SSH 别名并保存。默认每 2 秒采集一次；一次采集尚未结束时会跳过下一次，避免连接重叠。

4. 点击状态栏可展开或收起面板；点击空白处或按 Escape 可收起。「刷新」立即采集，「连接 SSH」会通过系统 SSH 链接处理程序打开终端连接。悬停状态栏可查看 CPU 和内存详情。

安装位置为 `~/Applications/SSH Monitor.app`。登录自启由 `~/Library/LaunchAgents/app.sshmonitor.menubar.plist` 提供。

## 故障排查

应用会显示连接失败或采集超时，并保留上次成功数据及其时间。可在终端直接检查采集结果：

```bash
~/Applications/'SSH Monitor.app'/Contents/MacOS/SSHMonitor --probe my-server
```

远端需要 Linux `/proc`；GPU 指标需要 `nvidia-smi`。SSH 使用本机已有的配置、密钥和 `known_hosts`，并强制主机密钥检查。仓库不包含真实主机名、地址、用户名、密钥或监控结果。应用只在本机 `UserDefaults` 保存 SSH 别名和刷新间隔；采集命令只读，不上传遥测数据。弹窗中的连接错误会隐藏具体地址，详细错误只在手动运行 `--probe` 时输出到本机终端。

## 卸载

先在面板中点击电源按钮退出，再运行：

```bash
launchctl bootout "gui/$(id -u)/app.sshmonitor.menubar"
rm -f ~/Library/LaunchAgents/app.sshmonitor.menubar.plist
rm -rf ~/Applications/'SSH Monitor.app'
```
