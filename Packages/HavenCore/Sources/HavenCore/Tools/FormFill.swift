import Foundation

/// The details people write on form after form, kept on this Mac for Fill & Sign.
public struct PersonalDetails: Codable, Equatable, Sendable {
    public var name = ""
    public var initials = ""
    public var email = ""
    public var phone = ""
    public var address = ""
    public var company = ""

    public init(name: String = "", initials: String = "", email: String = "", phone: String = "", address: String = "", company: String = "") {
        self.name = name
        self.initials = initials
        self.email = email
        self.phone = phone
        self.address = address
        self.company = company
    }

    /// One line in the My Details menu.
    public enum Field: String, CaseIterable, Identifiable, Sendable {
        case name, initials, email, phone, address, company

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .name: return "Name"
            case .initials: return "Initials"
            case .email: return "Email"
            case .phone: return "Phone"
            case .address: return "Address"
            case .company: return "Company"
            }
        }

        public var symbol: String {
            switch self {
            case .name: return "person"
            case .initials: return "textformat"
            case .email: return "envelope"
            case .phone: return "phone"
            case .address: return "house"
            case .company: return "building.2"
            }
        }
    }

    public func value(_ field: Field) -> String {
        switch field {
        case .name: return name.trimmed
        case .initials: return effectiveInitials
        case .email: return email.trimmed
        case .phone: return phone.trimmed
        case .address: return address.trimmingCharacters(in: .whitespacesAndNewlines)
        case .company: return company.trimmed
        }
    }

    /// The initials typed in, or worked out from the name ("Asha Rao" → "AR").
    public var effectiveInitials: String {
        if !initials.trimmed.isEmpty { return initials.trimmed }
        return name.split(whereSeparator: { $0 == " " || $0 == "-" }).compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    public var firstName: String { name.trimmed.split(separator: " ").first.map(String.init) ?? "" }

    public var lastName: String {
        let parts = name.trimmed.split(separator: " ")
        return parts.count > 1 ? String(parts[parts.count - 1]) : ""
    }

    public var isEmpty: Bool { Field.allCases.allSatisfy { value($0).isEmpty } }
}

/// How today's date is written on a form.
public enum DateStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case long, longUS, dayMonthYear, monthDayYear, iso, dotted

    public var id: String { rawValue }

    /// Day first everywhere except the United States.
    public static func standard(regionCode: String?) -> DateStyle { regionCode == "US" ? .longUS : .long }

    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                 "October", "November", "December"]

    /// "13 November 2026", "November 13, 2026", "13/11/2026", "11/13/2026", "2026-11-13" or "13.11.2026".
    public func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2000, m = c.month ?? 1, d = c.day ?? 1
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        switch self {
        case .long: return "\(d) \(Self.months[m - 1]) \(y)"
        case .longUS: return "\(Self.months[m - 1]) \(d), \(y)"
        case .dayMonthYear: return "\(two(d))/\(two(m))/\(y)"
        case .monthDayYear: return "\(two(m))/\(two(d))/\(y)"
        case .iso: return "\(y)-\(two(m))-\(two(d))"
        case .dotted: return "\(two(d)).\(two(m)).\(y)"
        }
    }
}

/// Works out what goes in a form field from its name ("Full Name", "applicant_email", "DateSigned").
public enum FormAutofill {
    /// What to put in the field, or nil when it isn't one of your details (or is a signature, a date of birth…).
    public static func value(forField fieldName: String, details: PersonalDetails, date: Date, style: DateStyle,
                             calendar: Calendar = .current) -> String? {
        let w = words(fieldName)
        guard !w.isEmpty else { return nil }
        func has(_ any: String...) -> Bool { any.contains { w.contains($0) } }
        func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

        // Signatures need a picture, not text; other people's details aren't yours.
        if has("sign", "signature") { return nil }
        if has("father", "mother", "spouse", "partner", "nominee", "witness", "guardian", "parent", "child", "emergency",
               "beneficiary", "reference", "referee", "bank", "account", "user", "username", "file", "doctor", "agent") { return nil }
        if has("initial", "initials") { return nonEmpty(details.effectiveInitials) }
        if has("email", "mail") { return nonEmpty(details.email.trimmed) }
        if has("phone", "telephone", "tel", "mobile", "cell") || (has("contact") && has("number", "no")) { return nonEmpty(details.phone.trimmed) }
        if has("company", "organisation", "organization", "employer", "business", "firm") { return nonEmpty(details.company.trimmed) }
        if has("date") || has("today") {
            if has("birth", "dob", "expiry", "expiration", "expires", "issue", "issued", "start", "end", "valid", "joining", "arrival", "departure") {
                return nil
            }
            return style.string(from: date, calendar: calendar)
        }
        if has("dob") { return nil }
        if has("city", "town", "zip", "postcode", "postal", "pin", "state", "country", "county", "province") { return nil }
        if has("address", "street", "addr") { return nonEmpty(details.address.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if has("middle") { return nil }
        if has("first", "given", "forename", "fname") { return nonEmpty(details.firstName) }
        if has("last", "surname", "family", "lname") { return nonEmpty(details.lastName) }
        if has("name") || w == ["applicant"] || w == ["full"] { return nonEmpty(details.name.trimmed) }
        return nil
    }

    /// "applicant_FullName2" → ["applicant", "full", "name"].
    static func words(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var prevLower = false
        for ch in s {
            if ch.isLetter {
                if ch.isUppercase, prevLower, !cur.isEmpty { out.append(cur); cur = "" }
                cur.append(Character(ch.lowercased()))
                prevLower = ch.isLowercase
            } else {
                if !cur.isEmpty { out.append(cur); cur = "" }
                prevLower = false
            }
        }
        if !cur.isEmpty { out.append(cur) }
        // Glued words people use in field names.
        return out.flatMap { word -> [String] in
            for glued in ["fullname", "firstname", "lastname", "surname", "middlename", "emailaddress", "phonenumber",
                          "datesigned", "signdate", "printname", "yourname"] where word == glued {
                switch word {
                case "fullname": return ["full", "name"]
                case "firstname": return ["first", "name"]
                case "lastname": return ["last", "name"]
                case "surname": return ["surname"]
                case "middlename": return ["middle", "name"]
                case "emailaddress": return ["email", "address"]
                case "phonenumber": return ["phone", "number"]
                case "datesigned": return ["date", "signed"]
                case "signdate": return ["sign", "date"]
                case "printname": return ["print", "name"]
                default: return ["your", "name"]
                }
            }
            return [word]
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
