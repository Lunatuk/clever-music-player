import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'cmp_file_ops',
      assetName: 'cmp_file_ops.dart',
      sources: ['src/cmp_file_ops.c'],
      flags: [
        if (input.config.code.targetOS == OS.android)
          '-Wl,-z,max-page-size=16384',
      ],
    ).run(input: input, output: output);
  });
}
