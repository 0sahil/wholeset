// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Problem report email")
struct ProblemReportTests {
    private let report = ProblemReport(
        appVersion: "1.0.1",
        build: "202611201530",
        deviceModel: "iPhone17,1",
        systemVersion: "iOS 26.1"
    )

    @Test func recipientIsTheSupportAddress() {
        #expect(ProblemReport.recipient == "0sahil.dev@gmail.com")
    }

    @Test func subjectNamesVersionAndBuild() {
        #expect(report.subject == "Wholeset 1.0.1 (202611201530): problem report")
    }

    @Test func bodyHasEmptyQuestionsThenTheDetails() {
        #expect(report.body == """
        What happened:


        Steps to reproduce:


        --
        App: Wholeset 1.0.1 (202611201530)
        iPhone: iPhone17,1, iOS 26.1
        Apple Watch: (model and watchOS version, if the problem was on the Watch)

        """)
    }

    @Test func aKnownWatchReplacesTheLineToFillIn() {
        let withWatch = ProblemReport(
            appVersion: "1.0.1", build: "7", deviceModel: "iPhone17,1", systemVersion: "iOS 26.1",
            watch: " Watch7,1, watchOS 26.1 "
        )
        #expect(withWatch.body.contains("Apple Watch: Watch7,1, watchOS 26.1\n"))
        #expect(!withWatch.body.contains("if the problem was on the Watch"))
    }

    @Test func blankValuesReadAsUnknown() {
        let blank = ProblemReport(appVersion: " ", build: "", deviceModel: "", systemVersion: "\n", watch: "  ")
        #expect(blank.subject == "Wholeset unknown (unknown): problem report")
        #expect(blank.body.contains("App: Wholeset unknown (unknown)\n"))
        #expect(blank.body.contains("iPhone: unknown, unknown\n"))
        #expect(blank.watch == nil)
    }

    @Test func mailtoURLCarriesRecipientSubjectAndBody() throws {
        let url = try #require(report.mailtoURL)
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:0sahil.dev@gmail.com?subject="))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == ProblemReport.recipient)
        let items = components.queryItems ?? []
        #expect(items.map(\.name) == ["subject", "body"])
        #expect(items.first?.value == report.subject)
        #expect(items.last?.value == report.body.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    /// Characters that delimit a URL query never split the subject or body.
    @Test func mailtoURLEncodesDelimiters() throws {
        let tricky = ProblemReport(appVersion: "1.0 & more", build: "a=b+c#d?e", deviceModel: "x", systemVersion: "y")
        let url = try #require(tricky.mailtoURL)
        let query = try #require(url.query(percentEncoded: true))
        #expect(!query.contains(" "))
        #expect(!query.contains("+"))
        #expect(!query.contains("#"))
        #expect(query.components(separatedBy: "&").count == 2)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first?.value == "Wholeset 1.0 & more (a=b+c#d?e): problem report")
        #expect(url.absoluteString.contains("%0D%0A"))
    }
}
