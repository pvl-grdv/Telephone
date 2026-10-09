//
//  AKSIPURIParser.swift
//  Telephone
//
//  Parses SIP and tel URIs received from PJSIP.
//

import Foundation

final class AKSIPURIParser {
    weak var agent: AKSIPUserAgent?

    init(userAgent: AKSIPUserAgent) {
        agent = userAgent
    }

    func sipURI(from string: String) -> AKSIPURI? {
        guard agent?.isStarted == true else {
            return nil
        }

        return parseSIPURI(string)
    }
}
