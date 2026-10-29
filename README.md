# Sub2API Watch

## 项目简介

个人 Apple Watch 用量监控：Node.js + TypeScript 查询服务与 SwiftUI 手表 App。打开 App 时刷新，支持手动刷新和离线快照。

```text
sub2api-watch/
├── README.md
├── server/                    # Node.js + TypeScript 查询服务
│   ├── src/
│   └── .env.example
└── watch/
    ├── Sub2APIWatch.xcodeproj  # Xcode 工程
    ├── Sub2APIWatch/           # Swift 源码与资源
    │   ├── Views/             # SwiftUI 界面
    │   └── Services/          # 网络请求与 Keychain
    └── demo.html              # 可交互界面原型
```

## 能查哪些数据？

- OpenAI 账号池各账号的 5 小时、7 天窗口剩余百分比及重置时间。
- 今日 token 用量，支持按用户绑定邮箱及其 API Key 名称筛选。
- 输入、输出、缓存 token 明细。

每日统计默认按北京时间计算，总 token 包含缓存用量。

## 如何配置

需要 Node.js 20.19 或更新版本。在 `~/.zshrc` 中添加：

```zsh
export SUB2API_ADMIN_API_KEY='你的 sub2api 管理 API Key'
export WATCH_API_KEY='为查询服务另设一个随机密钥'
export SUB2API_BASE_URL='http://127.0.0.1:8080' # 可选，默认本机
export SUB2API_TIMEZONE='Asia/Shanghai'        # 可选，默认北京时间
```

在项目根目录执行：

```zsh
source ~/.zshrc
cd server
npm install
npm run build
npm start
```

默认监听 `127.0.0.1:8787`，可通过 `HOST`、`PORT` 修改。远程访问时通过 HTTPS 反向代理连接。

请求携带 `Authorization: Bearer <WATCH_API_KEY>`：

- `GET /users`：用户邮箱列表。
- `GET /users/:id/keys`：该用户的 Key 名称列表。
- `GET /usage/today?userId=7&apiKeyId=12`：今日用量；省略 Key 查询该用户合计，省略两项查询全站。
- `GET /accounts`：账号窗口剩余额度；`stale` 表示刷新失败、使用旧快照，未知额度或无有效重置时间返回 `null`。

管理密钥仅保留在服务器，手表使用独立的 `WATCH_API_KEY`。

手表端需要 Mac、Xcode 15 或更新版本、watchOS 10 或更新版本。打开 `watch/Sub2APIWatch.xcodeproj`，选择 `Sub2APIWatch` Scheme 和 Apple Watch 模拟器运行；安装真机前，在 Signing & Capabilities 中选择自己的 Team，并修改 Bundle Identifier 为唯一标识。

在 App 的「连接设置」中填写手表可访问的 HTTPS 服务地址和 `WATCH_API_KEY`，密钥保存在 Keychain。Linux 上无法进行 Xcode 编译与实机验证；`watch/demo.html` 保留作界面对照。
