import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' hide AssetType;

final fileMediaRepositoryProvider = Provider((ref) => const FileMediaRepository());

class FileMediaRepository {
  const FileMediaRepository();

  Future<AssetEntity?> saveImageWithFile(String filePath, {String? title, String? relativePath}) async {
    final entity = await PhotoManager.editor.saveImageWithPath(filePath, title: title, relativePath: relativePath);
    return entity;
  }

  /// On iOS albums aren't folders, so the saved asset is added to [album] afterwards.
  Future<AssetEntity?> saveImageToAlbum(String filePath, {required String album, String? title}) async {
    final entity = await saveImageWithFile(
      filePath,
      title: title,
      relativePath: Platform.isAndroid ? 'Pictures/$album' : null,
    );
    if (entity == null || !Platform.isIOS) {
      return entity;
    }
    final albums = await PhotoManager.getAssetPathList(hasAll: false, type: RequestType.image);
    final target =
        albums.where((path) => path.name == album).firstOrNull ?? await PhotoManager.editor.darwin.createAlbum(album);
    if (target != null) {
      await PhotoManager.editor.copyAssetToPath(asset: entity, pathEntity: target);
    }
    return entity;
  }

  Future<AssetEntity?> saveLivePhoto({required File image, required File video, required String title}) async {
    final entity = await PhotoManager.editor.darwin.saveLivePhoto(imageFile: image, videoFile: video, title: title);
    return entity;
  }

  Future<AssetEntity?> saveVideo(File file, {required String title, String? relativePath}) async {
    final entity = await PhotoManager.editor.saveVideo(file, title: title, relativePath: relativePath);
    return entity;
  }
}
