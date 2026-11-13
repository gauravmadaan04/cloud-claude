import XCTest
@testable import HavenCore

final class FormFillTests: XCTestCase {
    let me = PersonalDetails(name: "Asha Rao", email: "asha@example.com", phone: "+91 98765 43210",
                             address: "Flat 4B, Linden Court\nNew Delhi", company: "Rao Design")
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let day = Date(timeIntervalSince1970: 1_794_528_000) // 13 November 2026, UTC

    func fill(_ field: String, _ style: DateStyle = .long) -> String? {
        FormAutofill.value(forField: field, details: me, date: day, style: style, calendar: utc)
    }

    func testDetails() {
        XCTAssertEqual(me.effectiveInitials, "AR")
        XCTAssertEqual(PersonalDetails(name: "Mary-Jane van Dyke").effectiveInitials, "MJVD")
        XCTAssertEqual(PersonalDetails(name: "Asha Rao", initials: "A.R.").effectiveInitials, "A.R.")
        XCTAssertEqual(me.firstName, "Asha")
        XCTAssertEqual(me.lastName, "Rao")
        XCTAssertEqual(PersonalDetails(name: "Cher").lastName, "")
        XCTAssertTrue(PersonalDetails().isEmpty)
        XCTAssertFalse(me.isEmpty)
        XCTAssertEqual(me.value(.address), "Flat 4B, Linden Court\nNew Delhi")
    }

    func testDateStyles() {
        XCTAssertEqual(DateStyle.long.string(from: day, calendar: utc), "13 November 2026")
        XCTAssertEqual(DateStyle.longUS.string(from: day, calendar: utc), "November 13, 2026")
        XCTAssertEqual(DateStyle.dayMonthYear.string(from: day, calendar: utc), "13/11/2026")
        XCTAssertEqual(DateStyle.monthDayYear.string(from: day, calendar: utc), "11/13/2026")
        XCTAssertEqual(DateStyle.iso.string(from: day, calendar: utc), "2026-11-13")
        XCTAssertEqual(DateStyle.dotted.string(from: day, calendar: utc), "13.11.2026")
        XCTAssertEqual(DateStyle.standard(regionCode: "US"), .longUS)
        XCTAssertEqual(DateStyle.standard(regionCode: "IN"), .long)
        XCTAssertEqual(DateStyle.standard(regionCode: nil), .long)
    }

    func testFieldNames() {
        XCTAssertEqual(fill("Full Name"), "Asha Rao")
        XCTAssertEqual(fill("applicant_FullName"), "Asha Rao")
        XCTAssertEqual(fill("Name"), "Asha Rao")
        XCTAssertEqual(fill("Print Name"), "Asha Rao")
        XCTAssertEqual(fill("First Name"), "Asha")
        XCTAssertEqual(fill("firstname"), "Asha")
        XCTAssertEqual(fill("Surname"), "Rao")
        XCTAssertEqual(fill("Last_Name"), "Rao")
        XCTAssertEqual(fill("Email Address"), "asha@example.com")
        XCTAssertEqual(fill("E-mail"), "asha@example.com")
        XCTAssertEqual(fill("Mobile No"), "+91 98765 43210")
        XCTAssertEqual(fill("Contact Number"), "+91 98765 43210")
        XCTAssertEqual(fill("Company Name"), "Rao Design")
        XCTAssertEqual(fill("Address"), "Flat 4B, Linden Court\nNew Delhi")
        XCTAssertEqual(fill("Initials"), "AR")
        XCTAssertEqual(fill("Date"), "13 November 2026")
        XCTAssertEqual(fill("DateSigned", .iso), "2026-11-13")
        XCTAssertEqual(fill("Today's date", .monthDayYear), "11/13/2026")
    }

    func testFieldsThatArentYours() {
        XCTAssertNil(fill("Signature"))
        XCTAssertNil(fill("Sign here"))
        XCTAssertNil(fill("Date of Birth"))
        XCTAssertNil(fill("DOB"))
        XCTAssertNil(fill("Passport expiry date"))
        XCTAssertNil(fill("Father's Name"))
        XCTAssertNil(fill("Nominee name"))
        XCTAssertNil(fill("Bank name"))
        XCTAssertNil(fill("Username"))
        XCTAssertNil(fill("City"))
        XCTAssertNil(fill("PIN code"))
        XCTAssertNil(fill("Middle Name"))
        XCTAssertNil(fill("Amount"))
        XCTAssertNil(fill(""))
        XCTAssertNil(FormAutofill.value(forField: "Email", details: PersonalDetails(name: "Asha"), date: day, style: .long, calendar: utc),
                     "nothing to put in: leave the field alone")
    }
}
