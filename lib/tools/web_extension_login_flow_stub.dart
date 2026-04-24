class WebExtensionLoginFlow {
  const WebExtensionLoginFlow();

  Stream<WebExtensionLoginState> get events async* {}

  Future<void> start() async {}

  Future<void> dispose() async {}
}

class WebExtensionLoginState {
  const WebExtensionLoginState.started()
    : type = WebExtensionLoginStateKind.started,
      message = null;
  const WebExtensionLoginState.complete()
    : type = WebExtensionLoginStateKind.complete,
      message = null;
  const WebExtensionLoginState.failed(this.message)
    : type = WebExtensionLoginStateKind.failed;

  final WebExtensionLoginStateKind type;
  final String? message;

  bool get isStarted => type == WebExtensionLoginStateKind.started;
  bool get isComplete => type == WebExtensionLoginStateKind.complete;
  bool get isFailed => type == WebExtensionLoginStateKind.failed;
}

enum WebExtensionLoginStateKind { started, complete, failed }
