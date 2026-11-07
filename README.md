# HGHub iOS

HGHub 的第三方 iOS 移植版：免登录浏览与播放短剧。

- 上游：[Minireel/HGhub](https://github.com/Minireel/HGhub)（Rust + Tauri 2 + React，Windows / macOS / Android），本仓库是按其接口地图做的原生 SwiftUI iOS 版，与红果官方 App 无关，也与 `jackotom/hongguo-drama` 无关。
- 接口：单一边缘入口 `POST /api/edge/request`（method / path / base64 body + 可选 Bearer），无签名、无设备注册、无 CENC。播放是普通 HLS AES-128，AVPlayer 原生播放；封面是 AES-128-CBC 密文，本地解密后显示。
- 许可证：PolyForm Noncommercial 1.0.0（见 `LICENSE`），**仅限个人学习、研究与自用**，禁止任何商业用途（出售、广告、会员、付费点播）。分发时须附带许可证全文与 Required Notice。

## v1 范围（游客浏览 + 播放 + 登录社区）

- 首页推荐流（无限滚动）与榜单（热门 / 推荐 / 潜力）
- 分类（4 个固定分类）与搜索（热门搜索词，查询参数为 `q`）
- 详情：封面、简介、标签、评分、分集列表、关注作者
- 播放：AVPlayer 直接播每集现取的播放地址（`auth_key` 约 1 小时过期，每集现取、不缓存地址），断点续看（本地记录，5 秒保存一次），播完自动下一集，倍速，全屏横屏；播放器里可点赞（按集）、收藏、看评论并发评论（登录后）
- 社区：吃瓜帖子列表与详情（正文 + 图片 + 视频）、帖子点赞 / 收藏、帖子评论只读（上游没有发帖评论的接口）
- 我的：登录 / 注册（token 存 Keychain，约 7 天过期，401 自动清掉重登）、本地观看记录、线路切换（`huangguoai.com` / `huangguoai.ai`）、清理缓存 / 记录、关于

**不做**：下载 / 合并 / 投屏。所有分集均可直接播，无付费墙。

## 构建

xcodegen + CI 出未签名 IPA，SideStore / AltStore 安装：

```sh
brew install xcodegen
xcodegen generate
```

CI（`.github/workflows/build.yml`）在 push 到 main 时自动构建并发布未签名 IPA（同时留一份 workflow artifact 兜底）。

## 真机测试清单（待验）

1. 首页加载出内容，封面正常显示（封面解密生效）。
2. 搜索能出结果；分类切换正常。
3. 详情页分集齐全，点任意一集能播。
4. 冒烟测试：视频 117 第 3 集直接在 AVPlayer 里播放（原仓库自检用的同一集）。
5. 续看：播到一半退出，再进详情页显示“继续观看”，能从断点接着播。
6. 自动下一集、倍速、全屏横屏正常。
7. 换线路后内容仍能加载。
8. 社区：帖子列表能刷出，点进详情有正文、图片、评论；登录后帖子点赞 / 收藏生效，视频评论能发，播放器里点赞（按集）/ 收藏 / 关注生效；退出登录后互动按钮会弹登录页。

> 注意：上游接口与封面密钥都未公开文档化，随时可能变化；先在真机上按上面清单验一遍，再当作可用。
