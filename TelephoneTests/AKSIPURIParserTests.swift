import Testing
import UseCases

struct AKSIPURIParserTests {
    @Test func decodesQuotedDisplayNamesExactlyOnce() throws {
        let cases: [(String, String)] = [
            (#""ООО \"Пример\"""#, #"ООО "Пример""#),
            (#""\"Пример\"""#, #""Пример""#),
            (#""Caller \"\"""#, #"Caller """#),
            (#""Support \\ Server""#, #"Support \ Server"#),
            (#""Support \\\"quoted\\\"""#, #"Support \"quoted\""#),
            (#""Backslash \\n stays literal""#, #"Backslash \n stays literal"#),
            (#""Escaped \A and \!""#, "Escaped A and !"),
            (#""  Caller  ""#, "  Caller  "),
            (#""""#, ""),
            ("\"Control \\\u{0001} and \\\u{007f}\"", "Control \u{0001} and \u{007f}"),
            ("\"\u{0301}Caller\"", "\u{0301}Caller"),
            (#""Caller &quot;Example&quot;""#, "Caller &quot;Example&quot;")
        ]

        for (encoded, expected) in cases {
            let uri = try #require(parseSIPURI("\(encoded) <sip:204@example.invalid>"))
            #expect(uri.displayName == expected)
            #expect(uri.user == "204")
            #expect(uri.host == "example.invalid")
        }
    }

    @Test func preservesUnquotedAndMalformedNames() throws {
        let names = [
            "Caller Name",
            #"Caller\Name"#,
            #"Caller "Example""#,
            #"Caller &quot;Example&quot;"#,
            #""Unclosed"#,
            #"Unopened""#,
            #"""#,
            #""Dangling\""#,
            #""Unescaped "quote" inside""#,
            #""Invalid \Ж escape""#,
            "\"Invalid \\\n escape\"",
            "\"Invalid \\\r escape\"",
            "\"Invalid \n newline\"",
            "\"Invalid \u{0001} control\""
        ]

        for name in names {
            let uri = try #require(parseSIPURI("\(name) <sip:204@example.invalid>"))
            #expect(uri.displayName == name)
        }
    }

    @Test func decodedNamesSurviveSerializationForRedial() throws {
        let names = [
            #"ООО "Пример""#,
            #"Caller "Example" Team"#,
            #"Support \ Server"#,
            #"Support \"quoted\""#,
            #"Backslash \n stays literal"#,
            "Control \u{0001} and \u{007f}",
            ""
        ]
        for name in names {
            let outbound = URI(
                user: "204",
                address: ServiceAddress(host: "example.invalid", port: "5061"),
                displayName: name,
                transport: .tls
            )
            let parsed = try #require(parseSIPURI(outbound.stringValue))
            #expect(parsed.displayName == name)
            #expect(parsed.user == "204")
            #expect(parsed.host == "example.invalid")
            #expect(parsed.port == 5061)
            let pasted = try #require(AKSIPURI(string: URI(
                user: "204", host: "example.invalid", displayName: name
            ).stringValue))
            #expect(pasted.displayName == name)
            let redial = try #require(parseSIPURI(parsed.description))
            #expect(redial == parsed)
        }
    }

    @Test func preservesAddressParsingAndWhitespace() throws {
        let uri = try #require(parseSIPURI(
            #"  "ООО \"Пример\""   <sips:user%22@[2001:db8::1]:5061;transport=tls?subject=example>  "#
        ))
        #expect(uri.displayName == #"ООО "Пример""#)
        #expect(uri.user == "user%22")
        #expect(uri.host == "2001:db8::1")
        #expect(uri.port == 5061)

        let tel = try #require(parseSIPURI(#""Caller \"Example\"" <tel:+123456789;ext=42>"#))
        #expect(tel.displayName == #"Caller "Example""#)
        #expect(tel.user == "+123456789")
        #expect(tel.host.isEmpty)

        let bare = try #require(parseSIPURI("sip:user%22@example.invalid:5070"))
        #expect(bare.displayName.isEmpty)
        #expect(bare.user == "user%22")
        #expect(bare.port == 5070)
        #expect(parseSIPURI("https://example.invalid") == nil)
        #expect(parseSIPURI("sip:") == nil)
        #expect(parseSIPURI("tel:") == nil)
    }
}
