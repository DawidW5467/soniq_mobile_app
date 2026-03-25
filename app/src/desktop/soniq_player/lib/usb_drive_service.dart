import 'dart:io';
import 'package:path/path.dart' as p;

class UsbDriveInfo {
  final String path;
  final String label;

  const UsbDriveInfo({required this.path, required this.label});
}

class UsbDriveService {
  static List<UsbDriveInfo> scan({String? user}) {
    final mountsFile = File('/proc/mounts');
    if (!mountsFile.existsSync()) return const [];

    final userName = user ?? Platform.environment['USER'] ?? '';
    final prefixes = <String>[
      if (userName.isNotEmpty) '/run/media/$userName/',
      if (userName.isNotEmpty) '/media/$userName/',
      '/media/',
    ];

    final allowedFs = <String>{
      'vfat',
      'exfat',
      'ntfs',
      'ext4',
      'ext3',
      'ext2',
      'fuseblk',
      'fuse.exfat',
      'fuse.ntfs',
      'fat',
      'msdos',
    };

    final seen = <String>{};
    final drives = <UsbDriveInfo>[];

    for (final line in mountsFile.readAsLinesSync()) {
      final parts = line.split(' ');
      if (parts.length < 3) continue;

      final mountPoint = _unescapeMountPath(parts[1]);
      final fsType = parts[2];

      if (!allowedFs.contains(fsType)) continue;
      if (!prefixes.any((prefix) => mountPoint.startsWith(prefix))) continue;
      if (mountPoint.endsWith('/')) continue;
      if (mountPoint == '/media' || mountPoint == '/run/media') continue;
      if (userName.isNotEmpty &&
          (mountPoint == '/media/$userName' || mountPoint == '/run/media/$userName')) {
        continue;
      }
      if (!Directory(mountPoint).existsSync()) continue;
      if (!seen.add(mountPoint)) continue;

      final label = p.basename(mountPoint);
      if (label.isEmpty) continue;

      drives.add(UsbDriveInfo(path: mountPoint, label: label));
    }

    drives.sort((a, b) {
      final labelCmp = a.label.compareTo(b.label);
      if (labelCmp != 0) return labelCmp;
      return a.path.compareTo(b.path);
    });

    return drives;
  }

  static String _unescapeMountPath(String value) {
    return value
        .replaceAll(r'\040', ' ')
        .replaceAll(r'\011', '\t')
        .replaceAll(r'\012', '\n')
        .replaceAll(r'\134', r'\');
  }
}

