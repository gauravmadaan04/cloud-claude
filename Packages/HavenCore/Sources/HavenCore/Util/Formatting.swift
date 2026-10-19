import Foundation

public enum HavenFormat {
    /// "Today, 10:42", "Yesterday", "Tuesday", "12 Mar", "12 Mar 2023".
    public static func friendlyDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            f.dateStyle = .none
            f.timeStyle = .short
            return "Today, " + f.string(from: date)
        }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days > 0 && days < 7 {
            f.setLocalizedDateFormatFromTemplate("EEEE")
            return f.string(from: date)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            f.setLocalizedDateFormatFromTemplate("d MMM")
            return f.string(from: date)
        }
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f.string(from: date)
    }

    /// "3 days ago", "2 months ago", "just now".
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "just now" }
        let m = Int(s / 60), h = Int(s / 3600), d = Int(s / 86_400)
        if m < 60 { return m == 1 ? "1 minute ago" : "\(m) minutes ago" }
        if h < 24 { return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        if d < 30 { return d == 1 ? "yesterday" : "\(d) days ago" }
        let months = d / 30
        if months < 12 { return months == 1 ? "a month ago" : "\(months) months ago" }
        let years = d / 365
        return years <= 1 ? "a year ago" : "\(years) years ago"
    }

    public static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let num = f.string(from: NSNumber(value: n)) ?? "\(n)"
        return "\(num) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
