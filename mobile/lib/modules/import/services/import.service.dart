import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/modules/import/providers/import.provider.dart';
import 'package:immich_mobile/shared/models/album.dart';
import 'package:immich_mobile/shared/providers/asset.provider.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

final importServiceProvider = Provider(
  (ref) => ImportService(
    ref: ref
  ),
);

class ImportService {

  final Logger _log = Logger("BackupService");
  final ref;

  late StreamSubscription _intentSub;

  ImportService({ required this.ref});

  init(){
    _log.info("UPLOAD INITTT");
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) async {
      await _onIntentReceived(files);
      ReceiveSharingIntent.instance.reset();
    }, onError: (err) {
      _log.info("getIntentDataStream error: $err");
    });
    ReceiveSharingIntent.instance.getInitialMedia().then((files) async {
        await _onIntentReceived(files);
        ReceiveSharingIntent.instance.reset();
    });
    
  }

  destroy(){
    _intentSub.cancel();
  }

  _onIntentReceived(List<SharedMediaFile> files) async {
    if(files.isEmpty){
      return;
    }

    List<AssetEntity> assetEntities = [];

    for(SharedMediaFile sharedFile in files){

      late AssetEntity? entity;
      File file = File(sharedFile.path);

      if(sharedFile.type == SharedMediaType.image){
        entity = await PhotoManager.editor.saveImageWithPath(
          sharedFile.path,
          title: basename(file.path),         
        );
      }

      if(sharedFile.type == SharedMediaType.video){
        var videoFile = File(sharedFile.path);
        entity = await PhotoManager.editor.saveVideo(
          videoFile,
          title: basename(file.path),
        );
      }

      await PhotoManager.getAssetPathList().then((value) => {
        for(var path in value){
          path.
        }
      });
      
      if(entity != null){
        assetEntities.add(entity);
      } else {
        _log.info("Failed to save file: ${sharedFile.path}");
      }
    }

    ref.watch(importProvider.notifier).registerIntent(assetEntities);
  }
}