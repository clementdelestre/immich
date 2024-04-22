
import 'package:photo_manager/photo_manager.dart';

enum ImportStateEnum {
  idle,
  importPrompted
}

class ImportState {

  final ImportStateEnum importState;
  final List<AssetEntity> assetEntities;

  const ImportState({
    required this.importState,
    required this.assetEntities,
  });

  ImportState copyWith({
    ImportStateEnum? importState,
    bool? hasFileToUpload,
    List<AssetEntity>? assetEntities,
  }) {
    return ImportState(
      importState: importState ?? this.importState,
      assetEntities: assetEntities ?? this.assetEntities,
    );
  }
}