//
//  PJString.swift
//  Telephone
//
//  Scoped string conversion at the PJSIP boundary.
//

import Foundation

func withPJString<Result>(
    _ value: String,
    _ body: (inout pj_str_t) -> Result
) -> Result {
    var bytes = Array(value.utf8CString)

    return bytes.withUnsafeMutableBufferPointer { buffer in
        var pjValue = pj_str(buffer.baseAddress)
        return body(&pjValue)
    }
}

func pjStringValue(_ value: pj_str_t) -> String {
    guard let pointer = value.ptr, value.slen > 0 else {
        return ""
    }

    let bytes = UnsafeRawBufferPointer(
        start: pointer,
        count: Int(value.slen)
    )
    return String(decoding: bytes, as: UTF8.self)
}
