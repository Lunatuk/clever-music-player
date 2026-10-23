import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const androidMediaAssetRoot = 'third_party/cmp_android_media/vendor';

final class AndroidMediaLicenses extends StatefulWidget {
  const AndroidMediaLicenses({super.key, this.assets, this.save});
  final AssetBundle? assets;
  final Future<String?> Function(Uint8List)? save;
  @override
  State<AndroidMediaLicenses> createState() => _AndroidMediaLicensesState();
}

final class _AndroidMediaLicensesState extends State<AndroidMediaLicenses> {
  late final _text = _loadText();
  bool _saving = false;
  String? _message;
  AssetBundle get _assets => widget.assets ?? rootBundle;
  Future<String> _loadText() async =>
      '${await _assets.loadString('$androidMediaAssetRoot/NOTICE.txt')}\n\n'
      '${await _assets.loadString('$androidMediaAssetRoot/COPYING.LGPLv2.1')}';
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final data = await _assets.load('$androidMediaAssetRoot/source-kit.zip');
      if (data.lengthInBytes > 16 * 1024 * 1024) throw const FormatException();
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final result = await (widget.save?.call(bytes) ??
          FilePicker.platform.saveFile(
              fileName: 'clever-android-ffmpeg-7.1.5-sources.zip',
              type: FileType.custom,
              allowedExtensions: const ['zip'],
              bytes: bytes));
      if (mounted) {
        setState(() => _message =
            result == null ? 'Сохранение отменено.' : 'Исходники сохранены.');
      }
    } on Object {
      if (mounted) {
        setState(() => _message =
            'Не удалось сохранить исходники. Можно повторить сохранение.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Лицензии и исходники')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('FFmpeg 7.1.5 · LGPL 2.1+'),
            const SizedBox(height: 8),
            const Text(
                'Соответствующие исходники, настройки сборки и инструкции '
                'по замене библиотек включены в приложение. Их можно сохранить без интернета.'),
            OutlinedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_alt),
                label: const Text('Сохранить исходники FFmpeg')),
            if (_saving) const LinearProgressIndicator(),
            if (_message != null) Text(_message!),
            const SizedBox(height: 16),
            FutureBuilder<String>(
                future: _text,
                builder: (context, snapshot) => snapshot.hasData
                    ? SelectableText(snapshot.data!)
                    : Text(snapshot.hasError
                        ? 'Не удалось открыть текст лицензии.'
                        : 'Загрузка лицензии…')),
          ])));
}
