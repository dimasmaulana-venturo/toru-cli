import XCTest
@testable import Toru_CLI

final class CommentFilterTests: XCTestCase {

    func testTableDriven() {
        let cases: [(input: String, expected: String?)] = [
            ("bun build", "bun build"),
            ("# note", nil),
            ("  # indented", nil),
            ("bun build # inline", "bun build # inline"),
            ("# a\nbun build\n# b", "bun build"),
            ("#!/bin/zsh", nil),
            ("## double", nil),
            ("", nil),
            ("\n\n", nil),
            ("ls\nls -la", "ls\nls -la"),
            ("# header\n  # indented\n# tail", nil),
            ("# build for prod\nbun run build\n# upload\ngcloud run deploy",
             "bun run build\ngcloud run deploy"),
        ]

        for (i, c) in cases.enumerated() {
            let got = CommentFilter.filter(c.input)
            XCTAssertEqual(got, c.expected,
                "case \(i): input=\(c.input.debugDescription) expected=\(c.expected.debugDescription) got=\(got.debugDescription)")
        }
    }

    func testIsCommentLine() {
        XCTAssertTrue(CommentFilter.isCommentLine("# x"))
        XCTAssertTrue(CommentFilter.isCommentLine("   # indent"))
        XCTAssertTrue(CommentFilter.isCommentLine("##"))
        XCTAssertFalse(CommentFilter.isCommentLine("bun"))
        XCTAssertFalse(CommentFilter.isCommentLine("bun # inline"))
        XCTAssertFalse(CommentFilter.isCommentLine(""))
    }
}
