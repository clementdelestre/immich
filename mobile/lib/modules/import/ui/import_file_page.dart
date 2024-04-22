import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/modules/import/providers/import.provider.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';

@RoutePage()
// ignore: must_be_immutable
class ImportFilePage extends HookConsumerWidget {
  final Logger _log = Logger("BackupService");

  ImportFilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    List<AssetEntity> assetEntities = ref.watch(importProvider).assetEntities;

    void importFile() async {  
      await ref.watch(importProvider.notifier).startImport();
      context.pop();
    }

    void cancelImport() async {
      ref.watch(importProvider.notifier).clearImport();
      context.pop();
    }

    buildAssetsList() {
      return assetEntities.map((e) {
        return ListTile(
          leading: const Icon(
            Icons.upload_file,
            size: 32,
          ),
          title: Text(e.title ?? ""),
          subtitle: Text(DateFormat.yMMMMd().format(e.modifiedDateTime).toString()),
        );
      }).toList();
    };

    return Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: false,
          backgroundColor: context.scaffoldBackgroundColor,
          leading: IconButton(
            onPressed: () {
              cancelImport();
            },
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Text(
            'upload_file_page_title',
          ).tr(),
        ),
        body: SafeArea(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 10),
                  child: Text(
                    'import_file_count',
                    style: context.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ).tr(args: ["${assetEntities.length}"]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: buildAssetsList(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: cancelImport,
                        child: const Text('action_common_cancel').tr(),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: importFile,
                        child: const Text('upload_file_upload').tr(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ));
  }
}
