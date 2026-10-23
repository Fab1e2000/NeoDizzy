import Foundation
import Testing
@testable import NeoDizzy

struct QQMusicLyricsTests {
    private func encoded(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    @Test func originalAndTranslationShareTimestamp() throws {
        let lyrics = try QQMusicClient.decodedLyrics([
            "lyric": encoded("[00:01.20]Hello\n[00:03.00]World"),
            "trans": encoded("[00:01.20]你好\n[00:03.00]世界")
        ])
        #expect(lyrics.lines.map(\.text) == ["Hello\n你好", "World\n世界"])
        #expect(lyrics.source == "QQ 音乐")
    }

    @Test func optionalTranslationCannotHideOriginalOrDuplicateIt() throws {
        let original = encoded("[00:01.00]原文")
        for translation in ["", "not base64!", original] {
            let lyrics = try QQMusicClient.decodedLyrics(["lyric": original, "trans": translation])
            #expect(lyrics.lines.map(\.text) == ["原文"])
        }
        #expect(throws: QQMusicError.self) { try QQMusicClient.decodedLyrics(["lyric": "not base64!"]) }
    }
}
