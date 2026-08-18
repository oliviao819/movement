// Local (on-device) reminder notifications. Deliberately not a push
// notification service — there's no server component here, so reminders are
// scheduled entirely with UNUserNotificationCenter. No Info.plist usage
// description is needed for this; the permission prompt is system-provided.

import Foundation
import UserNotifications

enum NotificationScheduler {
    private static let dailyReminderID = "movement.daily-reminder"

    /// Asks for notification permission if the member hasn't been asked yet
    /// (or already granted it). Safe to call repeatedly.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Schedules a repeating daily reminder at 7 PM local time. Doesn't check
    /// whether today's workout is already done before firing — that would
    /// need background refresh, which is out of scope for a simple reminder.
    static func scheduleDailyReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Time to move"
        content.body = "A few minutes today keeps your streak going."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 19
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: dailyReminderID, content: content, trigger: trigger)
        // Replaces any existing reminder with the same identifier, so calling
        // this again (e.g. on every launch) is idempotent.
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderID])
    }
}
