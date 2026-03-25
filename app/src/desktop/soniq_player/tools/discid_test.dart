import 'dart:io';
import 'package:soniq_player/metadata/libdiscid_ffi.dart';

void main() {
  final lib = LibDiscid.load();
  if (lib == null) {
    stderr.writeln('libdiscid.so not found. Install libdiscid (e.g., apt install libdiscid0).');
    exit(1);
  }
  final id = lib.computeDiscId();
  if (id == null || id.isEmpty) {
    stderr.writeln('Failed to compute Disc ID via libdiscid. Ensure a CD is in the drive and accessible (e.g., /dev/cdrom or /dev/sr0).');
    exit(2);
  }
  stdout.writeln('MusicBrainz Disc ID: $id');
}
