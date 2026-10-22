import 'dart:io';
import 'dart:typed_data';

/// DNS 结果不得把公开图片或直连请求导向本地、私有和组播地址。
bool isPublicAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final b = address.rawAddress;
  if (b.length == 4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127));
  }
  if (b.length != 16 || (b[0] & 0xfe) == 0xfc || b.every((v) => v == 0)) {
    return false;
  }
  if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
    return isPublicAddress(
      InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))),
    );
  }
  return true;
}
