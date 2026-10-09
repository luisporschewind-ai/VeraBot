import Foundation
import SwiftUI

/// 客户端配置。默认连接本机后端（模拟器可直接访问 Mac 的 127.0.0.1）。
/// 真机调试时请在登录页右上角「调试」里改为 Mac 的局域网 IP，例如 http://192.168.1.10:8000
enum AppConfig {
    static let defaultBaseURL = "http://127.0.0.1:8000"
}
