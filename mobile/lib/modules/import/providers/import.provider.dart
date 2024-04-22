
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/modules/import/models/import_state.model.dart';
import 'package:immich_mobile/shared/models/asset.dart';
import 'package:immich_mobile/shared/services/hash.service.dart';
import 'package:immich_mobile/shared/services/sync.service.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';

final importProvider =
    StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  return ImportNotifier(
    ref,
  );
});


class ImportNotifier extends StateNotifier<ImportState> {

  final log = Logger('ImportNotifier');
  final Ref ref;

  ImportNotifier(
    this.ref,
  ) : super(
    const ImportState(
      importState: ImportStateEnum.idle,
      assetEntities: [],
    ),
  );

  void setImportState(ImportStateEnum importState) {
    state = state.copyWith(importState: importState);
  }

  void setAssetEntities(List<AssetEntity> assetEntities) {
    state = state.copyWith(assetEntities: assetEntities);
  }

  Future<void> registerIntent(List<AssetEntity> files) async {
    setAssetEntities(files);
    setImportState(ImportStateEnum.importPrompted);
  }

  Future<void> startImport() async {

    List<Asset> assets = await ref.watch(hashServiceProvider).hashAssets(state.assetEntities);
      for(Asset asset in assets){
        await ref.watch(syncServiceProvider).syncNewAssetToDb(asset);
    }

    clearImport();
  }

  void clearImport() {
    setImportState(ImportStateEnum.idle);
    setAssetEntities([]);
  }
}