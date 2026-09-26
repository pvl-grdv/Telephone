//
//  AKSIPURIParser.swift
//  Telephone
//
//  Parses SIP and tel URIs received from PJSIP.
//

import Foundation

public final class AKSIPURIParser {
    public weak var agent: AKSIPUserAgent?

    public init(userAgent: AKSIPUserAgent) {
        agent = userAgent
    }

    public func sipURI(from string: String) -> AKSIPURI? {
        guard agent?.isStarted == true else {
            return nil
        }

        return parseSIPURI(string)
    }
}

private func parseSIPURI(_ input: String) -> AKSIPURI? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName: String
    let rawAddress: String

    if
        let open = trimmed.lastIndex(of: "<"),
        let close = trimmed.lastIndex(of: ">"),
        open < close
    {
        displayName = trimmed[..<open]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        rawAddress = String(
            trimmed[trimmed.index(after: open)..<close]
        )
    } else {
        displayName = ""
        rawAddress = trimmed
    }

    let lowercased = rawAddress.lowercased()

    if lowercased.hasPrefix("tel:") {
        let value = rawAddress.dropFirst(4)
        let number = value.split(
            separator: ";",
            maxSplits: 1
        ).first.map(String.init) ?? ""

        guard !number.isEmpty else {
            return nil
        }

        return AKSIPURI(
            user: number,
            host: "",
            displayName: displayName
        )
    }

    let schemeLength: Int
    if lowercased.hasPrefix("sip:") {
        schemeLength = 4
    } else if lowercased.hasPrefix("sips:") {
        schemeLength = 5
    } else {
        return nil
    }

    var destination = String(rawAddress.dropFirst(schemeLength))

    if let headers = destination.firstIndex(of: "?") {
        destination = String(destination[..<headers])
    }

    if let parameter = destination.firstIndex(of: ";") {
        destination = String(destination[..<parameter])
    }

    let user: String
    let hostAndPort: String

    if let at = destination.lastIndex(of: "@") {
        user = String(destination[..<at])
        hostAndPort = String(
            destination[destination.index(after: at)...]
        )
    } else {
        user = ""
        hostAndPort = destination
    }

    let address = parseServiceAddress(hostAndPort)

    guard !user.isEmpty || !address.host.isEmpty else {
        return nil
    }

    return AKSIPURI(
        user: user,
        host: address.host,
        displayName: displayName,
        port: address.port
    )
}

private func parseServiceAddress(
    _ value: String
) -> (host: String, port: Int) {
    if
        value.hasPrefix("["),
        let closingBracket = value.firstIndex(of: "]")
    {
        let host = String(
            value[value.index(after: value.startIndex)..<closingBracket]
        )

        let afterBracket = value.index(after: closingBracket)
        guard
            afterBracket < value.endIndex,
            value[afterBracket] == ":"
        else {
            return (host, 0)
        }

        let portStart = value.index(after: afterBracket)
        return (
            host,
            Int(value[portStart...]) ?? 0
        )
    }

    guard let colon = value.lastIndex(of: ":") else {
        return (value, 0)
    }

    let possiblePort = value[value.index(after: colon)...]
    guard
        !possiblePort.isEmpty,
        possiblePort.allSatisfy({ $0 >= "0" && $0 <= "9" })
    else {
        return (value, 0)
    }

    return (
        String(value[..<colon]),
        Int(possiblePort) ?? 0
    )
}
