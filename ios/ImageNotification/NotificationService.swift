import UniformTypeIdentifiers
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private var deliver: ((UNNotificationContent) -> Void)?
  private var content: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    deliver = contentHandler
    guard
      let content = request.content.mutableCopy() as? UNMutableNotificationContent,
      let url = Self.imageURL(in: request.content.userInfo)
    else {
      contentHandler(request.content)
      return
    }
    self.content = content
    URLSession.shared.downloadTask(with: url) { [weak self] location, response, _ in
      if let location, let attachment = Self.attachment(from: location, response: response) {
        content.attachments = [attachment]
      }
      self?.finish()
    }.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    finish()
  }

  private func finish() {
    guard let deliver, let content else { return }
    self.deliver = nil
    deliver(content)
  }

  private static func imageURL(in info: [AnyHashable: Any]) -> URL? {
    let options = info["fcm_options"] as? [String: Any]
    let candidates = [options?["image"], info["image"], info["imageUrl"], info["image_url"]]
    for case let raw as String in candidates {
      if let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), url.scheme == "https" {
        return url
      }
    }
    return nil
  }

  private static func attachment(from location: URL, response: URLResponse?) -> UNNotificationAttachment? {
    let type = response?.mimeType.flatMap { UTType(mimeType: $0) } ?? .png
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(type.preferredFilenameExtension ?? "png")
    do {
      try FileManager.default.moveItem(at: location, to: file)
      return try UNNotificationAttachment(identifier: "image", url: file)
    } catch {
      return nil
    }
  }
}
