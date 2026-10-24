# DSH Thinking Icon

把 DeepSeek Harness 聊天界面里「深度思考中」左边那颗动态鲸鱼尾小图标，换成你自己的贴纸 GIF。

Replace the animated whale-tail icon next to the **深度思考中 / thinking** status row in DeepSeek Harness with your own sticker GIF.

![preview](预览.png)

## 效果 / What it does

- 思考进行中时，状态行左侧显示自定义 GIF（18px，4 帧呼吸动画）
- 仅改一处 CSS，其它 UI、功能、数据完全不变
- 等长字节替换 `app.asar` 内嵌的 `client.js`，不重打包、不改文件大小

## 安装 / Install

1. 退出 DeepSeek Harness（含托盘）
2. 双击 `安装.cmd`
3. 重启 DeepSeek Harness

手动指定安装目录：

```powershell
powershell -ExecutionPolicy Bypass -File tools\install.ps1 -AsarPath "D:\你的目录\resources\app.asar"
```

## 还原 / Restore

双击 `还原.cmd`，从 `app.asar.bak` 恢复，然后重启应用。

若检测到应用已升级（指纹不一致），脚本会提示确认，避免把新版降级。

## 工作原理 / How it works

运行图标原本是一段内嵌 APNG 加 `mask` 的单色遮罩。脚本定位到这条规则：

```css
._runningWhaleAnimated{will-change:transform;background:currentColor;display:block;mask:url(data:image/png;base64,...)}
```

把规则体换成 `background-image` 引用贴纸 GIF，并用空格补齐到**完全相同的字节长度**，因此 asar 头、偏移、总大小都不变。

定位用的是特征匹配（`mask:url(data:image/png;base64,` + `_runningWhaleAnimated` 选择器），不依赖构建哈希，小版本更新后通常仍可用。

## 兼容性 / Compatibility

| 应用版本 | 状态 |
| --- | --- |
| 0.2.1-rc.2 | 已测试 |
| 0.2.1-rc.3 (nightly 2026-10-23) | 已测试 |

如果提示「未找到运行图标的遮罩规则」，说明 UI 结构变了，需要更新本工具。

## 已知限制 / Limitations

- 图标实际只有 18px，细节多的图会偏糊
- 贴纸是彩色位图，深色主题下不会跟随主题变色（原图标是单色遮罩）

## 安全 / Safety

- 不联网、不写注册表、不装服务
- 安装前自动备份 `app.asar.bak`，写入后校验，失败自动回滚
- 随时可用 `还原.cmd` 恢复

## License

代码 MIT。示例贴纸素材版权归原作者，仅作演示；正式发布请替换成你有权使用的图片。
