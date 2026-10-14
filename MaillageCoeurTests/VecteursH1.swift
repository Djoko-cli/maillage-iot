import CryptoKit
import Foundation
import MaillageCoeur

/// Vecteurs du pont Halo (benq 3a1ad2f, docs/PROTOCOLE-JSON.md 10.4), les memes que tools/host_tests/test_h1.cpp
/// et sonde-thread/test (firmware). Fichier sans test : compile par MaillageCoeurTests et par MaillageIoTTests
/// (CarteSimulee, canal et transport reseau Thread).
enum VecteursH1 {
    static let psk = Data((0..<32).map { UInt8($0) })
    static let na = Data((0xA0...0xAF).map { UInt8($0) })
    static let nc = "505152535455565758595A5B5C5D5E5F"
    static let sid = "1234ABCD"
    static let ks = "20D6D83D97ED44F2BBF8CE56389BD475CBE2B625CE6CE24768B6B4C1C625012F"
    static let salut = "H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D"
    static let defi = "H1 DEFI 1234ABCD 505152535455565758595A5B5C5D5E5F BFF13F71B42243E6017D2807F8E6171F"
    static let a1 = "H1 1234ABCD 1 FD97A0C9E604524B49C763452D0310CE id=1 json 1"
    static let chargeC1 = #"{"v":1,"t":"hb","n":7,"ms":1234}"#
    static let c1 = "H1 1234ABCD 1 347A2E6A129BC822ECFF39BEC910451C " + chargeC1

    static func session() -> SessionH1 {
        SessionH1(sid: sid, ks: H1.cleSession(cle: psk, na: na, nc: nc, sid: sid))
    }
}

func octets(_ s: String) -> Data { Data(s.utf8) }
