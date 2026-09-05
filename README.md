# Webplus - iOS 轻量浏览器

一个基于 WKWebView 的 iOS 浏览器，支持手势导航、多窗口、广告拦截、VLESS 代理、节点测速等功能。

## 当前版本：v15.5

## 功能特性

### 核心浏览功能
- 多窗口浏览（4个标签页，可自定义名称和地址）
- 右滑后退、左滑前进（跟随手指拖拽）
- 下拉刷新（70pt 触发高度）
- 双击右下角回顶部、双击左下角回底部
- 双击翻译键刷新当前网页
- 地址栏智能搜索（支持 Google/百度/Bing/DuckDuckGo）
- 地址栏双击复制当前 URL
- 地址栏位置可切换（顶部/底部，重启生效）

### 翻译功能
- 一键翻译当前网页（英文→中文）
- 翻译键长按弹出设置菜单
- 翻译键可自定义位置和大小

### 下载管理
- 原生 WKDownload 下载（iOS 15+）
- iOS 14 自动降级 URLSession 下载
- 下载进度条和角标提示
- 下载文件保存到 Documents/Downloads
- 支持在"文件"App 中查看下载内容

### 广告拦截
- 基于 WKContentRuleList 的域名拦截
- 全局图片广告拦截开关
- 自定义广告黑名单（支持添加/删除/编辑）
- 一键拦截当前网站所有图片
- 扩充版广告拦截黑名单

### 缓存管理
- 四级缓存系统（内存/瞬时/持久/磁盘）
- 24小时自动清空过期缓存
- 缓存管理页面显示手机存储状态和浏览器缓存大小
- 支持清空当前站点缓存和一键清空全部缓存

### VLESS 代理
- AppProxyExtension 网络扩展
- 支持直连模式和 VLESS-WS 模式
- VLESS 节点管理（添加/删除/切换）
- 节点延迟测速（批量测试，按延迟排序）
- 订阅管理器（支持 HTTP/HTTPS 订阅，Base64 解码）
- 支持解析 vless/vmess/trojan 节点

### 右边缘功能菜单
- 从屏幕右边缘滑出（50% 宽度）
- 弹出动画 1 秒
- 功能项可拖拽排序
- 包含：增加书签、书签列表、历史记录、下载管理、全局图片拦截、UA 切换、广告黑名单、缓存管理、高级代理、设置

### 设置功能
- 搜索引擎切换（Google/百度/Bing/DuckDuckGo）
- 地址栏位置切换（顶部/底部）
- 默认浏览器设置指引
- 版本号显示
- 权限管理（一键开启全部权限）

### 其他功能
- UA 切换（iPhone/iPad/Mac/Windows Chrome/Windows Edge）
- 网页内文字搜索（高亮匹配，上下跳转）
- 书签管理（长按标签添加/打开/管理）
- Safari 风格历史记录
- 四级缓存优化
- DNS 预解析和 TCP 预连接
- 禁止媒体自动播放
- 网页强制缩放

## 系统要求
- 最低 iOS 14.0
- 推荐 iOS 15.0+（支持原生 WKDownload）
- TrollStore 安装（推荐，永久签名）

## 安装方式
### TrollStore（推荐）
1. 彻底卸载旧版本
2. 用 TrollStore 打开 IPA 全新安装
3. 首次开启 VPN 代理需允许添加 VPN 配置

### 爱思助手
1. 连接手机到电脑
2. 用爱思助手导入 IPA 安装
3. 注意：AdHoc 证书需绑定设备 UDID

## 项目结构
```
WebViewBrowser/
├── ViewController.swift      # 主界面（浏览器核心逻辑）
├── DownloadManager.swift     # 下载管理器
├── VLESSClient.swift         # VLESS 客户端和节点管理
├── DownloadPanelViewController.swift  # 下载管理面板
├── Info.plist                # 应用配置
├── WebViewBrowser.entitlements  # 主App权限
└── Assets.xcassets/
AppProxyExtension/
├── AppProxyProvider.swift    # 代理核心（直连+VLESS）
├── VLESSClient.swift         # Extension用VLESS客户端
├── AppProxyExtension.entitlements  # Extension权限
└── Info.plist
.github/workflows/
└── build.yml                 # GitHub Actions 构建流程
```

## 构建
通过 GitHub Actions 自动构建：
1. 推送代码到 main 分支
2. 自动触发构建
3. 构建完成后在 Actions 页面下载 IPA
4. 使用用户证书签名（配置 GitHub Secrets）

## 版本历史
- v15.5: 修复下载功能语法错误、工具栏位置切换、缓存管理改造、全面汉化
- v15.4: 修复工具栏位置切换、默认浏览器指引、全汉化、VPN终极ldid签名
- v15.3: 设置移至侧边菜单、菜单速度1s、手势交换右滑后退左滑前进
- v15.2: 修复permission denied、下载bug、新增设置功能
- v15.1: 修复Extension签名问题，支持TrollStore
- v15.0: 新增节点延迟测试功能
- v14.9: iOS 14 降级兼容
