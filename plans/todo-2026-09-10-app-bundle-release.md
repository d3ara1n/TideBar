# App Bundle 打包与分发

## 目标

- [ ] `swift build` 产出可分发的 `TideBar.app`：bundle id `dev.dearain.TideBar`、版本号、应用图标、en/zh-Hans 显示名
- [ ] 构建产物用本地自签证书签名
- [ ] Release 产物发布到 GitHub Releases

## 边界

- 不公证，不上架 App Store。
- 打包脚本只产出构建产物，不注册任何系统状态。
- 不含登录项；登录项是打包之后的应用内功能，另行立案。
