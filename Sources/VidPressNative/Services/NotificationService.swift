import Foundation
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyQueueFinished(total: Int, failed: Int) {
        guard total > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "VidPress 压缩完成"
        content.body = failed > 0
            ? "\(total) 个任务已处理，其中 \(failed) 个失败。"
            : "\(total) 个任务已全部导出。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "vidpress.queue.finished.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
