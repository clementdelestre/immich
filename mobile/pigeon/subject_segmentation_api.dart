import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/subject_segmentation_api.g.dart',
    swiftOut: 'ios/Runner/Core/SubjectSegmentationApi.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/app/alextran/immich/segmentation/SubjectSegmentationApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'app.alextran.immich.segmentation'),
    dartOptions: DartOptions(),
    dartPackageName: 'immich_mobile',
  ),
)
class SubjectCutout {
  final Uint8List png;

  // Crop rect, normalized to the source image.
  final double left;
  final double top;
  final double width;
  final double height;

  const SubjectCutout({
    required this.png,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

@HostApi()
abstract class SubjectSegmentationApi {
  @async
  SubjectCutout? extractSubject(Uint8List rgba, int width, int height, double x, double y);

  void copyImageToClipboard(String path);
}
