import UIKit

// MARK: - 第三方平台定义
struct ThirdPartyPlatform {
    let name: String
    let schemes: [String]
    let iconName: String
    let color: UIColor
    let appStoreURL: String?
}

// MARK: - 第三方登录管理器
class ThirdPartyLoginManager {
    static let shared = ThirdPartyLoginManager()
    
    private init() {}
    
    // 支持的平台列表
    let platforms: [ThirdPartyPlatform] = [
        ThirdPartyPlatform(name: "微信", schemes: ["weixin", "wechat", "weixinULAPI"],
                          iconName: "message.circle.fill", color: UIColor(red: 0.03, green: 0.72, blue: 0.30, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id414478124"),
        ThirdPartyPlatform(name: "QQ", schemes: ["mqq", "mqqapi", "mqqopensdkapi"],
                          iconName: "person.crop.circle.fill", color: UIColor(red: 0.08, green: 0.58, blue: 0.94, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id444934666"),
        ThirdPartyPlatform(name: "支付宝", schemes: ["alipays", "alipay"],
                          iconName: "a.circle.fill", color: UIColor(red: 0.09, green: 0.54, blue: 0.97, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id333206289"),
        ThirdPartyPlatform(name: "微博", schemes: ["weibosdk", "weibo", "sinaweibo"],
                          iconName: "eye.circle.fill", color: UIColor(red: 0.86, green: 0.22, blue: 0.18, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id350962117"),
        ThirdPartyPlatform(name: "钉钉", schemes: ["dingtalk", "dingtalk-open"],
                          iconName: "briefcase.circle.fill", color: UIColor(red: 0.10, green: 0.53, blue: 0.96, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id930368978"),
        ThirdPartyPlatform(name: "淘宝", schemes: ["taobao", "tmall"],
                          iconName: "bag.circle.fill", color: UIColor(red: 0.94, green: 0.35, blue: 0.10, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id387682726"),
        ThirdPartyPlatform(name: "京东", schemes: ["jdopen", "openapp.jdmobile"],
                          iconName: "cart.circle.fill", color: UIColor(red: 0.89, green: 0.12, blue: 0.12, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id414245413"),
        ThirdPartyPlatform(name: "抖音", schemes: ["douyin", "snssdk1128"],
                          iconName: "music.note.circle.fill", color: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id1142110895"),
        ThirdPartyPlatform(name: "小红书", schemes: ["xhsdiscover", "xhs"],
                          iconName: "book.circle.fill", color: UIColor(red: 0.93, green: 0.20, blue: 0.28, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id741292507"),
        ThirdPartyPlatform(name: "B站", schemes: ["bilibili", "bilibiliwhite"],
                          iconName: "tv.circle.fill", color: UIColor(red: 0.11, green: 0.76, blue: 0.95, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id736536674"),
        ThirdPartyPlatform(name: "知乎", schemes: ["zhihu"],
                          iconName: "questionmark.circle.fill", color: UIColor(red: 0.04, green: 0.42, blue: 0.86, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id432274380"),
        ThirdPartyPlatform(name: "网易云音乐", schemes: ["neteasemusic", "orpheus"],
                          iconName: "music.circle.fill", color: UIColor(red: 0.86, green: 0.16, blue: 0.17, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id590338362"),
        ThirdPartyPlatform(name: "百度地图", schemes: ["baidumap"],
                          iconName: "map.circle.fill", color: UIColor(red: 0.11, green: 0.65, blue: 0.95, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id461709860"),
        ThirdPartyPlatform(name: "高德地图", schemes: ["iosamap", "amapuri", "amap"],
                          iconName: "map.fill", color: UIColor(red: 0.0, green: 0.56, blue: 0.31, alpha: 1),
                          appStoreURL: "https://apps.apple.com/app/id461709860"),
    ]
    
    // 判断URL是否为第三方登录/唤起
    func isThirdPartyURL(_ url: URL) -> (Bool, ThirdPartyPlatform?) {
        let scheme = url.scheme?.lowercased() ?? ""
        for platform in platforms {
            if platform.schemes.contains(scheme) {
                return (true, platform)
            }
        }
        // 检查host中是否包含平台关键词（用于网页授权跳转）
        let host = url.host?.lowercased() ?? ""
        let thirdPartyHosts = ["open.weixin.qq.com", "open.qzone.qq.com", "connect.qq.com",
                               "openauth.alipay.com", "api.weibo.com", "passport.baidu.com"]
        for h in thirdPartyHosts {
            if host.contains(h) {
                // 尝试匹配平台
                if host.contains("weixin") || host.contains("wechat") {
                    return (true, platforms[0])
                } else if host.contains("qq") {
                    return (true, platforms[1])
                } else if host.contains("alipay") {
                    return (true, platforms[2])
                } else if host.contains("weibo") {
                    return (true, platforms[3])
                }
            }
        }
        return (false, nil)
    }
    
    // 判断是否已安装对应App
    func isAppInstalled(_ platform: ThirdPartyPlatform) -> Bool {
        for scheme in platform.schemes {
            if let url = URL(string: "\(scheme)://") {
                if UIApplication.shared.canOpenURL(url) {
                    return true
                }
            }
        }
        return false
    }
    
    // 唤起App
    func openApp(url: URL, completion: @escaping (Bool) -> Void) {
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
    
    // 生成平台显示名称
    func displayName(for url: URL) -> String {
        let (_, platform) = isThirdPartyURL(url)
        return platform?.name ?? "第三方应用"
    }
}
