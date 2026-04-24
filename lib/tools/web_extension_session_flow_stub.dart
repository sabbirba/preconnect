class WebExtensionSessionFlow {
  const WebExtensionSessionFlow();
  Stream<WebExtensionSessionEvent> get events => const Stream.empty();
  Future<void> dispose() async {}
}

class WebExtensionSessionEvent {
  const WebExtensionSessionEvent.logoutComplete()
    : type = WebExtensionSessionEventKind.logoutComplete;

  final WebExtensionSessionEventKind type;
}

enum WebExtensionSessionEventKind { logoutComplete }
