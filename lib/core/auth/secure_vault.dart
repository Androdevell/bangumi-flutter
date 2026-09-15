import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

abstract interface class SecureVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract class PlatformSecureVault implements SecureVault {
  factory PlatformSecureVault() {
    if (Platform.isAndroid) return _AndroidSecureVault();
    if (Platform.isWindows) return _WindowsSecureVault();
    throw UnsupportedError(
      'Secure storage is only available on Android and Windows',
    );
  }
}

class _AndroidSecureVault implements PlatformSecureVault {
  static const _channel = MethodChannel('com.xiaoyv.bangumi/secure-storage');

  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', {'key': key});
}

class _WindowsSecureVault implements PlatformSecureVault {
  _WindowsSecureVault()
    : _crypt32 = DynamicLibrary.open('crypt32.dll'),
      _kernel32 = DynamicLibrary.open('kernel32.dll') {
    _protect = _crypt32.lookupFunction<_CryptProtectNative, _CryptProtect>(
      'CryptProtectData',
    );
    _unprotect = _crypt32
        .lookupFunction<_CryptUnprotectNative, _CryptUnprotect>(
          'CryptUnprotectData',
        );
    _localFree = _kernel32.lookupFunction<_LocalFreeNative, _LocalFree>(
      'LocalFree',
    );
    _getLastError = _kernel32
        .lookupFunction<_GetLastErrorNative, _GetLastError>('GetLastError');
  }

  static const _uiForbidden = 0x1;

  final DynamicLibrary _crypt32;
  final DynamicLibrary _kernel32;
  late final _CryptProtect _protect;
  late final _CryptUnprotect _unprotect;
  late final _LocalFree _localFree;
  late final _GetLastError _getLastError;

  @override
  Future<String?> read(String key) async {
    final file = await _fileFor(key);
    if (!await file.exists()) return null;
    try {
      final encrypted = base64Decode(await file.readAsString());
      return utf8.decode(_transform(encrypted, decrypt: true));
    } on Object {
      if (await file.exists()) await file.delete();
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _fileFor(key);
    final encrypted = _transform(utf8.encode(value), decrypt: false);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(base64Encode(encrypted), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String key) async {
    final file = await _fileFor(key);
    if (await file.exists()) await file.delete();
  }

  Future<File> _fileFor(String key) async {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw StateError('Windows APPDATA directory is unavailable');
    }
    final directory = Directory(
      '$appData${Platform.pathSeparator}BangumiFlutter'
      '${Platform.pathSeparator}secure',
    );
    await directory.create(recursive: true);
    final fileName = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('${directory.path}${Platform.pathSeparator}$fileName.dat');
  }

  List<int> _transform(List<int> bytes, {required bool decrypt}) {
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final inputBytes = calloc<Uint8>(bytes.length);
    try {
      inputBytes.asTypedList(bytes.length).setAll(0, bytes);
      input.ref
        ..length = bytes.length
        ..data = inputBytes;
      final success =
          decrypt
              ? _unprotect(
                input,
                nullptr.cast<Pointer<Utf16>>(),
                nullptr.cast<_DataBlob>(),
                nullptr,
                nullptr,
                _uiForbidden,
                output,
              )
              : _protect(
                input,
                nullptr.cast<Utf16>(),
                nullptr.cast<_DataBlob>(),
                nullptr,
                nullptr,
                _uiForbidden,
                output,
              );
      if (success == 0) {
        throw StateError('Windows DPAPI failed with error ${_getLastError()}');
      }
      return List<int>.from(output.ref.data.asTypedList(output.ref.length));
    } finally {
      if (output.ref.data.address != 0) _localFree(output.ref.data.cast());
      calloc.free(inputBytes);
      calloc.free(input);
      calloc.free(output);
    }
  }
}

final class _DataBlob extends Struct {
  @Uint32()
  external int length;

  external Pointer<Uint8> data;
}

typedef _CryptProtectNative =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _CryptProtect =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
typedef _CryptUnprotectNative =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Pointer<Utf16>>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _CryptUnprotect =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Pointer<Utf16>>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFree = Pointer<Void> Function(Pointer<Void>);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastError = int Function();

class MemorySecureVault implements SecureVault {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
