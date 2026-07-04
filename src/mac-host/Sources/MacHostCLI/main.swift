import Foundation
import Dispatch
import MacHostKit

@main
struct MacHostCLI {
    static func main() {
        let config = parseArguments(CommandLine.arguments)
        let app = MacHost(configuration: config)
        Task {
            let started = await app.start()
            if !started {
                exit(1)
            }
            // --inject-test / --virtual-display-probe 等自测模式完成后直接退出，不需要常驻事件循环。
            if config.injectTestPath != nil || config.virtualDisplayProbe {
                exit(0)
            }
        }
        dispatchMain()
    }

    private static func parseArguments(_ arguments: [String]) -> Configuration {
        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            exit(0)
        }

        var config = Configuration()
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--width":
                if i + 1 < arguments.count { config.width = Int(arguments[i + 1]) ?? config.width; i += 1 }
            case "--height":
                if i + 1 < arguments.count { config.height = Int(arguments[i + 1]) ?? config.height; i += 1 }
            case "--fps":
                if i + 1 < arguments.count { config.fps = Double(arguments[i + 1]) ?? config.fps; i += 1 }
            case "--bitrate":
                if i + 1 < arguments.count { config.bitrate = Int(arguments[i + 1]) ?? config.bitrate; i += 1 }
            case "--port":
                if i + 1 < arguments.count { config.port = UInt16(arguments[i + 1]) ?? config.port; i += 1 }
            case "--dump":
                if i + 1 < arguments.count { config.dumpPath = arguments[i + 1]; i += 1 }
            case "--dump-duration":
                if i + 1 < arguments.count { config.dumpDuration = Double(arguments[i + 1]) ?? config.dumpDuration; i += 1 }
            case "--profile":
                if i + 1 < arguments.count {
                    if let profile = Profile(arguments[i + 1]) {
                        config.profile = profile
                    } else {
                        fputs("未知 profile: \(arguments[i + 1])，可用: \(Profile.allCases.map(\.rawValue).joined(separator: ", "))\n", stderr)
                        exit(1)
                    }
                    i += 1
                }
            case "--hello-fixture":
                if i + 1 < arguments.count { config.helloFixturePath = arguments[i + 1]; i += 1 }
            case "--inject-test":
                if i + 1 < arguments.count { config.injectTestPath = arguments[i + 1]; i += 1 }
            case "--skip-input-permission-check":
                config.skipInputPermissionCheck = true
            case "--virtual-display-probe":
                config.virtualDisplayProbe = true
            case "--probe-output":
                if i + 1 < arguments.count { config.virtualDisplayProbeOutputPath = arguments[i + 1]; i += 1 }
            case "--mirror":
                config.useVirtualDisplay = false
            default:
                break
            }
            i += 1
        }
        return config
    }

    private static func printUsage() {
        print("""
        Usage: machost [options]

        Options:
          --profile <name>         输出档位: balanced, hd60, detected-native-safe, detected-native
          --hello-fixture <path>   从 JSON 文件加载 Android HELLO 用于自测
          --dump <path>            采集到本地 Annex B 文件，不启动 TCP
          --dump-duration <sec>    dump 时长（默认 5 秒）
          --inject-test <path>     读取本地 JSON 事件序列测试输入注入，不启动 TCP/采集
          --skip-input-permission-check  跳过 Accessibility 权限检查（仅调试用）
          --virtual-display-probe  创建虚拟显示器 POC（不启动 TCP/采集）
          --probe-output <path>    POC 采集帧保存路径（默认 /tmp/machost-virtual-display-frame.jpg）
          --mirror                 回退到 M1 镜像主屏（不创建虚拟显示器）
          --width, --height, --fps, --bitrate  自定义输出参数（未指定 --profile 时生效）
          --port <port>            TCP 监听端口（默认 19421）
          --help, -h               显示帮助
        """)
    }
}
