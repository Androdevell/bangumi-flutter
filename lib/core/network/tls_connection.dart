import 'dart:io';

/// 自定义 HttpClient.connectionFactory 必须自行为 HTTPS 建立 TLS。
/// 保持原始域名和系统信任链，不设置放行证书的回调。
ConnectionTask<Socket> authenticateConnection(
  Uri uri,
  ConnectionTask<Socket> task,
) {
  if (uri.scheme != 'https') return task;
  return ConnectionTask.fromSocket(
    task.socket.then((socket) async {
      try {
        return await SecureSocket.secure(socket, host: uri.host);
      } on Object {
        socket.destroy();
        rethrow;
      }
    }),
    task.cancel,
  );
}
