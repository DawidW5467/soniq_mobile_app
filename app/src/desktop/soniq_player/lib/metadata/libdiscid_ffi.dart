import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

/// Prosty binding do libdiscid (https://github.com/metabrainz/libdiscid)
/// Wymaga zainstalowanego `libdiscid.so` w systemie.
class LibDiscid {
  LibDiscid._(this._lib);
  final ffi.DynamicLibrary _lib;

  static LibDiscid? load({String? path}) {
    try {
      final lib = path != null
          ? ffi.DynamicLibrary.open(path)
          : ffi.DynamicLibrary.open('libdiscid.so');
      return LibDiscid._(lib);
    } catch (_) {
      return null;
    }
  }

  late final _discid_new = _lib.lookupFunction<ffi.Pointer<ffi.Void> Function(), ffi.Pointer<ffi.Void> Function()>('discid_new');
  late final _discid_free = _lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>), void Function(ffi.Pointer<ffi.Void>)>('discid_free');
  late final _discid_read = _lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>), int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>)>('discid_read');
  late final _discid_get_id = _lib.lookupFunction<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>), ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>)>('discid_get_id');

  /// Oblicz Disc ID; zwraca null jeśli brak.
  String? computeDiscId({String? device}) {
    final h = _discid_new();
    if (h == ffi.Pointer<ffi.Void>.fromAddress(0)) return null;
    try {
      final dev = (device ?? '/dev/cdrom').toNativeUtf8();
      final ok = _discid_read(h, dev);
      calloc.free(dev);
      if (ok == 0) {
        // Spróbuj inne urządzenie
        final dev2 = '/dev/sr0'.toNativeUtf8();
        final ok2 = _discid_read(h, dev2);
        calloc.free(dev2);
        if (ok2 == 0) {
          return null;
        }
      }
      final ptr = _discid_get_id(h);
      if (ptr.address == 0) return null;
      final id = ptr.toDartString();
      return id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    } finally {
      _discid_free(h);
    }
  }
}
