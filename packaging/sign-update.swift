import CryptoKit
import Foundation

// 发布流程用：给安装包签名，输出 base64 的 64 字节 Ed25519 签名。
// 用法：printf '%s' "$UPDATE_SIGNING_KEY" | swift packaging/sign-update.swift 安装包.pkg > 安装包.pkg.sig
// 私钥（32 字节种子的 base64）只从标准输入读，不写进任何文件。

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { fail("用法：swift packaging/sign-update.swift 安装包") }

let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let seed = Data(base64Encoded: input), seed.count == 32 else {
    fail("私钥格式不对：应该是 32 字节种子的 base64")
}
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let package = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
print(try key.signature(for: package).base64EncodedString())
