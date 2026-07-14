import 'dart:io';

import '../../application/notifiers/log_notifier.dart';

/// Reusable, directly testable socket error callback.
///
/// Keeping the callback in an object avoids duplicating lifecycle behavior in
/// each protocol server and makes the error path deterministic in tests.
final class SocketErrorGuard {
  SocketErrorGuard({
    required this.channel,
    required this.address,
    required this.socket,
    required this.clients,
    void Function()? destroy,
  }) : _destroy = destroy ?? socket.destroy;

  final String channel;
  final String address;
  final Socket socket;
  final List<Socket> clients;
  final void Function() _destroy;

  void call(Object error) {
    clients.remove(socket);
    globalLog.warning(channel, 'Client error ($address): $error');
    try {
      _destroy();
    } catch (cleanupError) {
      globalLog.warning(
        channel,
        'Client cleanup failed ($address): $cleanupError',
      );
    }
  }
}
