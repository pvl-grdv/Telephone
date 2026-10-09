// RFC 3261 quoted-string: remove exactly one enclosing pair, then decode
// quoted-pairs once. Unquoted or malformed names are preserved verbatim.
func decodeSIPDisplayName(_ value: String) -> String {
    let scalars = value.unicodeScalars
    guard scalars.count >= 2, scalars.first == "\"", scalars.last == "\"" else {
        return value
    }

    var decoded = String.UnicodeScalarView()
    var escaped = false
    for scalar in scalars.dropFirst().dropLast() {
        if escaped {
            // quoted-pair allows ASCII except CR and LF, not escaped Unicode.
            guard scalar.value <= 0x7f, scalar.value != 0x0a, scalar.value != 0x0d else {
                return value
            }
            decoded.append(scalar)
            escaped = false
        } else if scalar == "\\" {
            escaped = true
        } else if scalar == "\"" {
            return value
        } else {
            guard scalar == "\t" || (scalar.value >= 0x20 && scalar.value != 0x7f) else {
                return value
            }
            decoded.append(scalar)
        }
    }
    guard !escaped else { return value }
    return String(decoded)
}


// Escape a semantic display name for use inside SIP quoted-string delimiters.
func encodeSIPDisplayName(_ value: String) -> String {
    var encoded = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
        let isQuotedControl = (scalar.value < 0x20 && scalar != "\t"
            && scalar != "\r" && scalar != "\n") || scalar.value == 0x7f
        if scalar == "\\" || scalar == "\"" || isQuotedControl {
            encoded.append("\\")
        }
        encoded.append(scalar)
    }
    return String(encoded)
}
