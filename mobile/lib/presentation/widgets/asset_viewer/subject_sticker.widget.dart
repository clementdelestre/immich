import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/infrastructure/loaders/image_request.dart';
import 'package:immich_mobile/platform/subject_segmentation_api.g.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/repositories/file_media.repository.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/photo_view/photo_view.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final _api = SubjectSegmentationApi();

Future<SubjectCutout?> extractSubjectCutout(BaseAsset asset, ImageProvider displayed, Offset point) async {
  final image = await _loadOriginal(asset) ?? await _resolve(displayed);
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return await _api.extractSubject(rgba!.buffer.asUint8List(), image.width, image.height, point.dx, point.dy);
  } finally {
    image.dispose();
  }
}

// The viewer decodes at screen size, which would make the sticker blurry.
Future<ui.Image?> _loadOriginal(BaseAsset asset) async {
  final localId = asset.localId;
  final remoteId = asset.remoteId;
  final ImageRequest? request = localId != null && !asset.isEdited
      ? LocalImageRequest(localId: localId, size: Size.zero, assetType: asset.type)
      : remoteId != null
      ? RemoteImageRequest(uri: getOriginalUrlForRemoteId(remoteId, edited: asset.isEdited))
      : null;
  try {
    return (await request?.load(PaintingBinding.instance.instantiateImageCodecWithSize))?.image;
  } catch (_) {
    return null;
  }
}

Future<ui.Image> _resolve(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (error, stack) {
      stream.removeListener(listener);
      completer.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

class SubjectStickerOverlay extends ConsumerStatefulWidget {
  final Offset point;
  final Future<SubjectCutout?> cutout;
  final PhotoViewControllerBase controller;
  final Size viewportSize;
  final VoidCallback onDismiss;

  const SubjectStickerOverlay({
    super.key,
    required this.point,
    required this.cutout,
    required this.controller,
    required this.viewportSize,
    required this.onDismiss,
  });

  @override
  ConsumerState<SubjectStickerOverlay> createState() => _SubjectStickerOverlayState();
}

class _SubjectStickerOverlayState extends ConsumerState<SubjectStickerOverlay> with TickerProviderStateMixin {
  late final _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  late final _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  StreamSubscription<PhotoViewControllerValue>? _controllerSub;
  SubjectCutout? _cutout;
  ui.Image? _sticker;
  File? _file;

  @override
  void initState() {
    super.initState();
    _controllerSub = widget.controller.outputStateStream.listen((_) => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_controllerSub?.cancel());
    _sticker?.dispose();
    _wave.dispose();
    _shimmer.dispose();
    _lift.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    SubjectCutout? cutout;
    File? file;
    ui.Image? sticker;
    try {
      cutout = await widget.cutout;
      if (cutout != null) {
        final name = 'sticker-${DateTime.now().millisecondsSinceEpoch}.png';
        file = await File(p.join((await getTemporaryDirectory()).path, name)).writeAsBytes(cutout.png);
        sticker = await decodeImageFromList(cutout.png);
      }
    } catch (_) {
      cutout = null;
    }
    if (!mounted) {
      sticker?.dispose();
      return;
    }
    if (cutout == null || sticker == null) {
      ImmichToast.show(context: context, msg: context.t.scaffold_body_error_occurred, toastType: ToastType.error);
      widget.onDismiss();
      return;
    }
    _wave.stop();
    unawaited(_shimmer.repeat());
    unawaited(_lift.forward());
    setState(() {
      _cutout = cutout;
      _file = file;
      _sticker = sticker;
    });
  }

  Rect get _imageRect {
    final value = widget.controller.value;
    final childSize = widget.controller.scaleBoundaries?.childSize ?? widget.viewportSize;
    final scale = value.scale ?? 1;
    return Rect.fromCenter(
      center: widget.viewportSize.center(Offset.zero) + value.position,
      width: childSize.width * scale,
      height: childSize.height * scale,
    );
  }

  Future<void> _copy() async {
    await _api.copyImageToClipboard(_file!.path);
    widget.onDismiss();
  }

  Future<void> _share() async {
    await Share.shareXFiles([XFile(_file!.path)]);
  }

  static const _stickerAlbum = 'Stickers';

  Future<void> _save() async {
    final backgroundSync = ref.read(backgroundSyncProvider);
    await ref
        .read(fileMediaRepositoryProvider)
        .saveImageToAlbum(_file!.path, album: _stickerAlbum, title: p.basename(_file!.path));
    // New device photos only show up in the timeline after a local sync.
    unawaited(backgroundSync.syncLocal());
    if (mounted) {
      ImmichToast.show(
        context: context,
        msg: context.t.saved_to_album(album: _stickerAlbum),
        toastType: ToastType.success,
      );
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageRect = _imageRect;
    final cutout = _cutout;
    final sticker = _sticker;

    final children = <Widget>[];
    if (cutout == null || sticker == null) {
      final origin = imageRect.topLeft + Offset(widget.point.dx * imageRect.width, widget.point.dy * imageRect.height);
      children.add(
        Positioned.fill(
          child: CustomPaint(
            painter: _WavePainter(_wave, origin: origin, clip: imageRect),
          ),
        ),
      );
    } else {
      final subjectRect = Rect.fromLTWH(
        imageRect.left + cutout.left * imageRect.width,
        imageRect.top + cutout.top * imageRect.height,
        cutout.width * imageRect.width,
        cutout.height * imageRect.height,
      );
      final padding = MediaQuery.paddingOf(context);
      final above = subjectRect.top - 72;
      final barTop = above > padding.top + 8
          ? above
          : math.min(subjectRect.bottom + 16, widget.viewportSize.height - padding.bottom - 72);

      children.addAll([
        Positioned.fromRect(
          rect: imageRect,
          child: FadeTransition(
            opacity: _lift,
            child: const ColoredBox(color: Colors.black45),
          ),
        ),
        Positioned.fromRect(
          rect: subjectRect.inflate(_StickerPainter.margin),
          child: ScaleTransition(
            scale: _lift.drive(
              TweenSequence([
                TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06), weight: 1),
                TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.02), weight: 1),
              ]).chain(CurveTween(curve: Curves.easeOut)),
            ),
            child: CustomPaint(painter: _StickerPainter(sticker, blink: _shimmer)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: barTop,
          child: Center(
            child: FadeTransition(
              opacity: _lift,
              child: _ActionBar(onCopy: _copy, onShare: _share, onSave: _save),
            ),
          ),
        ),
      ]);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => didPop ? null : widget.onDismiss(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        child: Stack(children: children),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  static const _rings = 2;

  // About 1.5 cm.
  static const _maxRadius = 90.0;

  final Animation<double> progress;
  final Offset origin;
  final Rect clip;

  _WavePainter(this.progress, {required this.origin, required this.clip}) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(clip);
    for (var i = 0; i < _rings; i++) {
      final t = (progress.value + i / _rings) % 1;
      canvas.drawCircle(
        origin,
        Curves.easeOut.transform(t) * _maxRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 + 6 * t
          ..color = Colors.white.withValues(alpha: 0.6 * (1 - t))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 4 * t),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.origin != origin || old.clip != clip;
}

class _StickerPainter extends CustomPainter {
  static const margin = 8.0;
  static const _outlineWidth = 2.0;
  static const _stamps = 16;

  // Opaque white where the subject is more than half opaque.
  static const _hardWhite = ColorFilter.matrix([
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 0, 16, -8 * 255,
  ]);

  // Same threshold as the outline so both edges line up.
  static const _hardEdge = ColorFilter.matrix([
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 16, -8 * 255,
  ]);

  final ui.Image sticker;
  final Animation<double> blink;

  _StickerPainter(this.sticker, {required this.blink}) : super(repaint: blink);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Offset.zero & Size(sticker.width.toDouble(), sticker.height.toDouble());
    final dst = (Offset.zero & size).deflate(margin);
    final white = Paint()
      ..colorFilter = _hardWhite
      ..filterQuality = FilterQuality.medium;
    final opacity = 0.7 + 0.3 * math.cos(blink.value * 2 * math.pi);

    // Stamping the silhouette around a circle gives a crisp outline, ImageFilter.dilate renders it blurry.
    canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: opacity));
    for (var i = 0; i < _stamps; i++) {
      final angle = i * 2 * math.pi / _stamps;
      canvas.drawImageRect(sticker, src, dst.shift(Offset(math.cos(angle), math.sin(angle)) * _outlineWidth), white);
    }
    canvas.drawImageRect(sticker, src, dst, Paint.from(white)..blendMode = BlendMode.dstOut);
    canvas.restore();

    canvas.drawImageRect(
      sticker,
      src,
      dst,
      Paint()
        ..colorFilter = _hardEdge
        ..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_StickerPainter old) => old.sticker != sticker;
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onSave;

  const _ActionBar({required this.onCopy, required this.onShare, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onCopy, child: Text(context.t.copy_image)),
            TextButton(onPressed: onShare, child: Text(context.t.share)),
            TextButton(onPressed: onSave, child: Text(context.t.save)),
          ],
        ),
      ),
    );
  }
}
