import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'kundi_glb_audit.dart' as audit;

const _glbMagic = 0x46546c67;
const _jsonChunkType = 0x4e4f534a;
const _binChunkType = 0x004e4942;

const _preservedAnimations = <String>{
  'Standing',
  'Idle',
  'Waiting',
  'Talking',
  'Talking2',
  'Talking3',
  'Dansing',
};

const _preservedMorphs = <String>{
  'Fcl_ALL_Neutral',
  'Fcl_ALL_Joy',
  'Fcl_ALL_Fun',
  'Fcl_ALL_Sorrow',
  'Fcl_ALL_Surprised',
  'Fcl_ALL_Angry',
  'Fcl_EYE_Close',
  'Fcl_EYE_Close_R',
  'Fcl_EYE_Close_L',
  'Fcl_MTH_A',
  'Fcl_MTH_I',
  'Fcl_MTH_U',
  'Fcl_MTH_E',
  'Fcl_MTH_O',
};

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final profile = _OptimizationProfile.named(options.profile);
  final sourceBytes = File(options.input).readAsBytesSync();
  final document = _GlbDocument.parse(sourceBytes);
  final temp = Directory.systemTemp.createTempSync('kundi-glb-optimize-');

  try {
    final optimizedImages = options.reuseImagesFrom == null
        ? await _encodeImages(
            document,
            temp,
            profile,
            options.toktx!,
          )
        : _readOptimizedImages(options.reuseImagesFrom!);
    final result = _optimizeDocument(document, optimizedImages);
    final output = File(options.output)..parent.createSync(recursive: true);
    output.writeAsBytesSync(result.toBytes(), flush: true);

    final report = audit.auditGlb(
      output.readAsBytesSync(),
      path: output.path,
      dpr: options.dpr,
      heroWidth: options.heroWidth,
      heroHeight: options.heroHeight,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'profile': profile.name,
        'toktxVersion': options.toktxVersion,
        'imageSource': options.reuseImagesFrom ?? 'toktx',
        'preservedAnimations': _preservedAnimations.toList()..sort(),
        'preservedMorphs': _preservedMorphs.toList()..sort(),
        'audit': report,
      }),
    );
  } finally {
    final tempPath = temp.absolute.path;
    final systemTempPath = Directory.systemTemp.absolute.path;
    if (!tempPath.startsWith('$systemTempPath${Platform.pathSeparator}')) {
      throw StateError('Refusing to remove unexpected temp path: $tempPath');
    }
    temp.deleteSync(recursive: true);
  }
}

List<_OptimizedImage> _readOptimizedImages(String path) {
  final source = File(path);
  if (!source.existsSync()) {
    throw ArgumentError.value(path, 'reuse-images-from', 'GLB does not exist');
  }
  final document = _GlbDocument.parse(source.readAsBytesSync());
  final images = _mapList(document.json['images']);
  final bufferViews = _mapList(document.json['bufferViews']);
  return List<_OptimizedImage>.generate(images.length, (index) {
    final image = images[index];
    if (image['mimeType'] != 'image/ktx2') {
      throw StateError('Reusable image $index is not KTX2.');
    }
    final viewIndex = _int(image['bufferView'], fallback: -1);
    if (viewIndex < 0 || viewIndex >= bufferViews.length) {
      throw StateError('Reusable image $index has no embedded bufferView.');
    }
    final view = bufferViews[viewIndex];
    final start = _int(view['byteOffset']);
    final length = _int(view['byteLength']);
    return _OptimizedImage(
      name: image['name'] as String?,
      bytes: Uint8List.sublistView(document.bin, start, start + length),
    );
  });
}

Future<List<_OptimizedImage>> _encodeImages(
  _GlbDocument document,
  Directory temp,
  _OptimizationProfile profile,
  String toktx,
) async {
  final images = _mapList(document.json['images']);
  final bufferViews = _mapList(document.json['bufferViews']);
  final results = <_OptimizedImage>[];

  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    final mimeType = image['mimeType'] as String?;
    if (mimeType != 'image/png' && mimeType != 'image/jpeg') {
      throw StateError('Unsupported source image mime type: $mimeType');
    }
    final viewIndex = _int(image['bufferView'], fallback: -1);
    if (viewIndex < 0 || viewIndex >= bufferViews.length) {
      throw StateError('Image $index has no embedded bufferView.');
    }
    final view = bufferViews[viewIndex];
    final start = _int(view['byteOffset']);
    final length = _int(view['byteLength']);
    final extension = mimeType == 'image/png' ? 'png' : 'jpg';
    final input =
        File('${temp.path}${Platform.pathSeparator}image_$index.$extension');
    input.writeAsBytesSync(
      Uint8List.sublistView(document.bin, start, start + length),
      flush: true,
    );
    final output =
        File('${temp.path}${Platform.pathSeparator}image_$index.ktx2');
    final spec = profile.images[index];
    if (spec == null) {
      throw StateError('Profile ${profile.name} has no image spec for $index.');
    }
    final args = <String>[
      '--t2',
      '--genmipmap',
      '--filter',
      'lanczos4',
      '--resize',
      '${spec.size}x${spec.size}',
      '--encode',
      spec.encoding,
      if (spec.encoding == 'uastc') ...[
        '--uastc_quality',
        '${spec.quality}',
        '--zcmp',
        '5',
      ] else ...[
        '--clevel',
        '2',
        '--qlevel',
        '${spec.quality}',
      ],
      '--assign_oetf',
      spec.normalMap ? 'linear' : 'srgb',
      if (spec.normalMap) ...[
        '--normal_mode',
        '--input_swizzle',
        'rgb1',
      ],
      '--threads',
      '4',
      output.path,
      input.path,
    ];
    final process = await Process.run(toktx, args);
    if (process.exitCode != 0 || !output.existsSync()) {
      throw StateError(
        'toktx failed for image $index (${process.exitCode}): '
        '${process.stdout}\n${process.stderr}',
      );
    }
    results.add(
      _OptimizedImage(
        name: image['name'] as String?,
        bytes: output.readAsBytesSync(),
      ),
    );
  }
  return results;
}

_GlbDocument _optimizeDocument(
  _GlbDocument source,
  List<_OptimizedImage> images,
) {
  final json = _deepCopyMap(source.json);
  final originalAccessors = _mapList(json['accessors']);
  final originalBufferViews = _mapList(json['bufferViews']);

  final animations = _mapList(json['animations'])
      .where((item) => _preservedAnimations.contains(item['name']))
      .toList(growable: false);
  final animationNames = animations.map((item) => item['name']).toSet();
  if (!animationNames.containsAll(_preservedAnimations) ||
      animationNames.length != _preservedAnimations.length) {
    throw StateError('Required animation clips are missing: $animationNames');
  }
  json['animations'] = animations;

  final meshes = _mapList(json['meshes']);
  final targetIndicesByMesh = <int, List<int>>{};
  for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
    final mesh = meshes[meshIndex];
    final extras = _map(mesh['extras']);
    final targetNames = _stringList(extras?['targetNames']);
    if (targetNames.isEmpty) continue;
    final keptIndices = <int>[];
    final keptNames = <String>[];
    for (var targetIndex = 0; targetIndex < targetNames.length; targetIndex++) {
      final name = targetNames[targetIndex];
      if (_preservedMorphs.contains(name)) {
        keptIndices.add(targetIndex);
        keptNames.add(name);
      }
    }
    if (!keptNames.toSet().containsAll(_preservedMorphs)) {
      throw StateError(
        'Mesh ${mesh['name']} does not contain the required morph set.',
      );
    }
    targetIndicesByMesh[meshIndex] = keptIndices;
    extras!['targetNames'] = keptNames;
    mesh['extras'] = extras;
    final weights = _list(mesh['weights']);
    if (weights.isNotEmpty) {
      mesh['weights'] = [for (final index in keptIndices) weights[index]];
    }
    final primitives = _mapList(mesh['primitives']);
    for (final primitive in primitives) {
      final targets = _mapList(primitive['targets']);
      primitive['targets'] = [for (final index in keptIndices) targets[index]];
    }
    mesh['primitives'] = primitives;
  }
  json['meshes'] = meshes;

  final nodes = _mapList(json['nodes']);
  for (final node in nodes) {
    final meshIndex = _int(node['mesh'], fallback: -1);
    final keptIndices = targetIndicesByMesh[meshIndex];
    final weights = _list(node['weights']);
    if (keptIndices != null && weights.isNotEmpty) {
      node['weights'] = [for (final index in keptIndices) weights[index]];
    }
  }
  json['nodes'] = nodes;

  final usedAccessors = _collectUsedAccessors(json);
  final sortedAccessorIndices = usedAccessors.toList()..sort();
  final accessorRemap = <int, int>{};
  final accessors = <Map<String, Object?>>[];
  for (final oldIndex in sortedAccessorIndices) {
    if (oldIndex < 0 || oldIndex >= originalAccessors.length) {
      throw StateError('Invalid accessor reference: $oldIndex');
    }
    accessorRemap[oldIndex] = accessors.length;
    accessors.add(_deepCopyMap(originalAccessors[oldIndex]));
  }
  _remapAccessorReferences(json, accessorRemap);
  json['accessors'] = accessors;

  final binBuilder = BytesBuilder(copy: false);
  final newBufferViews = <Map<String, Object?>>[];
  final wholeViewRemap = <int, int>{};
  final segmentRemap = <String, int>{};

  int copyWholeView(int oldIndex) {
    final existing = wholeViewRemap[oldIndex];
    if (existing != null) return existing;
    if (oldIndex < 0 || oldIndex >= originalBufferViews.length) {
      throw StateError('Invalid bufferView reference: $oldIndex');
    }
    final old = originalBufferViews[oldIndex];
    final start = _int(old['byteOffset']);
    final length = _int(old['byteLength']);
    _align4(binBuilder);
    final newIndex = newBufferViews.length;
    final next = _deepCopyMap(old)
      ..['buffer'] = 0
      ..['byteOffset'] = binBuilder.length;
    newBufferViews.add(next);
    binBuilder.add(Uint8List.sublistView(source.bin, start, start + length));
    wholeViewRemap[oldIndex] = newIndex;
    return newIndex;
  }

  int copySegment(int oldViewIndex, int relativeOffset, int length) {
    final key = '$oldViewIndex:$relativeOffset:$length';
    final existing = segmentRemap[key];
    if (existing != null) return existing;
    final old = originalBufferViews[oldViewIndex];
    final start = _int(old['byteOffset']) + relativeOffset;
    _align4(binBuilder);
    final newIndex = newBufferViews.length;
    newBufferViews.add({
      'buffer': 0,
      'byteOffset': binBuilder.length,
      'byteLength': length,
    });
    binBuilder.add(Uint8List.sublistView(source.bin, start, start + length));
    segmentRemap[key] = newIndex;
    return newIndex;
  }

  for (final accessor in accessors) {
    final view = accessor['bufferView'];
    if (view is num) {
      accessor['bufferView'] = copyWholeView(view.toInt());
    }
    final sparse = _map(accessor['sparse']);
    if (sparse == null) continue;
    final sparseCount = _int(sparse['count']);
    final indices = _map(sparse['indices'])!;
    final values = _map(sparse['values'])!;
    final indicesView = _int(indices['bufferView']);
    final valuesView = _int(values['bufferView']);
    final indicesOffset = _int(indices['byteOffset']);
    final valuesOffset = _int(values['byteOffset']);
    final indicesLength =
        sparseCount * _componentBytes(_int(indices['componentType']));
    final valuesLength = sparseCount *
        _componentCount(accessor['type'] as String?) *
        _componentBytes(_int(accessor['componentType']));
    indices['bufferView'] =
        copySegment(indicesView, indicesOffset, indicesLength);
    indices['byteOffset'] = 0;
    values['bufferView'] = copySegment(valuesView, valuesOffset, valuesLength);
    values['byteOffset'] = 0;
    sparse['indices'] = indices;
    sparse['values'] = values;
    accessor['sparse'] = sparse;
  }

  final nextImages = <Map<String, Object?>>[];
  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    _align4(binBuilder);
    final viewIndex = newBufferViews.length;
    newBufferViews.add({
      'buffer': 0,
      'byteOffset': binBuilder.length,
      'byteLength': image.bytes.length,
      'name': 'kundi_${index}_ktx2',
    });
    binBuilder.add(image.bytes);
    nextImages.add({
      if (image.name != null) 'name': image.name,
      'mimeType': 'image/ktx2',
      'bufferView': viewIndex,
    });
  }
  json['images'] = nextImages;

  final textures = _mapList(json['textures']);
  for (final texture in textures) {
    final sourceIndex = _int(texture.remove('source'), fallback: -1);
    if (sourceIndex < 0 || sourceIndex >= nextImages.length) {
      throw StateError('Texture has an invalid source image: $sourceIndex');
    }
    final extensions = _map(texture['extensions']) ?? <String, Object?>{};
    extensions['KHR_texture_basisu'] = {'source': sourceIndex};
    texture['extensions'] = extensions;
  }
  json['textures'] = textures;

  final extensionsUsed = _stringList(json['extensionsUsed']).toSet()
    ..add('KHR_texture_basisu');
  final extensionsRequired = _stringList(json['extensionsRequired']).toSet()
    ..add('KHR_texture_basisu');
  json['extensionsUsed'] = extensionsUsed.toList()..sort();
  json['extensionsRequired'] = extensionsRequired.toList()..sort();

  _align4(binBuilder);
  final bin = binBuilder.takeBytes();
  json['bufferViews'] = newBufferViews;
  json['buffers'] = [
    {'byteLength': bin.length},
  ];
  return _GlbDocument(json, bin);
}

Set<int> _collectUsedAccessors(Map<String, Object?> json) {
  final used = <int>{};
  for (final mesh in _mapList(json['meshes'])) {
    for (final primitive in _mapList(mesh['primitives'])) {
      final indices = primitive['indices'];
      if (indices is num) used.add(indices.toInt());
      final attributes = _map(primitive['attributes']) ?? const {};
      for (final value in attributes.values) {
        if (value is num) used.add(value.toInt());
      }
      for (final target in _mapList(primitive['targets'])) {
        for (final value in target.values) {
          if (value is num) used.add(value.toInt());
        }
      }
    }
  }
  for (final animation in _mapList(json['animations'])) {
    for (final sampler in _mapList(animation['samplers'])) {
      final input = sampler['input'];
      final output = sampler['output'];
      if (input is num) used.add(input.toInt());
      if (output is num) used.add(output.toInt());
    }
  }
  for (final skin in _mapList(json['skins'])) {
    final inverse = skin['inverseBindMatrices'];
    if (inverse is num) used.add(inverse.toInt());
  }
  return used;
}

void _remapAccessorReferences(
  Map<String, Object?> json,
  Map<int, int> remap,
) {
  int mapped(Object? value) {
    final old = _int(value, fallback: -1);
    final next = remap[old];
    if (next == null) {
      throw StateError('Accessor $old was pruned but referenced.');
    }
    return next;
  }

  final meshes = _mapList(json['meshes']);
  for (final mesh in meshes) {
    final primitives = _mapList(mesh['primitives']);
    for (final primitive in primitives) {
      if (primitive['indices'] != null) {
        primitive['indices'] = mapped(primitive['indices']);
      }
      final attributes = _map(primitive['attributes'])!;
      for (final key in attributes.keys.toList()) {
        attributes[key] = mapped(attributes[key]);
      }
      primitive['attributes'] = attributes;
      final targets = _mapList(primitive['targets']);
      for (final target in targets) {
        for (final key in target.keys.toList()) {
          target[key] = mapped(target[key]);
        }
      }
      primitive['targets'] = targets;
    }
    mesh['primitives'] = primitives;
  }
  json['meshes'] = meshes;

  final animations = _mapList(json['animations']);
  for (final animation in animations) {
    final samplers = _mapList(animation['samplers']);
    for (final sampler in samplers) {
      sampler['input'] = mapped(sampler['input']);
      sampler['output'] = mapped(sampler['output']);
    }
    animation['samplers'] = samplers;
  }
  json['animations'] = animations;

  final skins = _mapList(json['skins']);
  for (final skin in skins) {
    if (skin['inverseBindMatrices'] != null) {
      skin['inverseBindMatrices'] = mapped(skin['inverseBindMatrices']);
    }
  }
  json['skins'] = skins;
}

void _align4(BytesBuilder builder) {
  final remainder = builder.length % 4;
  if (remainder != 0) builder.add(Uint8List(4 - remainder));
}

int _componentBytes(int componentType) => switch (componentType) {
      5120 || 5121 => 1,
      5122 || 5123 => 2,
      5125 || 5126 => 4,
      _ => throw StateError('Unsupported component type: $componentType'),
    };

int _componentCount(String? type) => switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' || 'MAT2' => 4,
      'MAT3' => 9,
      'MAT4' => 16,
      _ => throw StateError('Unsupported accessor type: $type'),
    };

final class _GlbDocument {
  _GlbDocument(this.json, this.bin);

  factory _GlbDocument.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 20 || data.getUint32(0, Endian.little) != _glbMagic) {
      throw const FormatException('Input is not a GLB file.');
    }
    if (data.getUint32(4, Endian.little) != 2 ||
        data.getUint32(8, Endian.little) != bytes.length) {
      throw const FormatException('Unsupported or malformed GLB.');
    }
    Uint8List? jsonBytes;
    Uint8List? binBytes;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(offset, Endian.little);
      final type = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      final end = start + length;
      if (end > bytes.length) throw const FormatException('Invalid GLB chunk.');
      if (type == _jsonChunkType) {
        jsonBytes = Uint8List.sublistView(bytes, start, end);
      } else if (type == _binChunkType) {
        binBytes = Uint8List.sublistView(bytes, start, end);
      }
      offset = end;
    }
    if (jsonBytes == null || binBytes == null) {
      throw const FormatException('GLB JSON or BIN chunk is missing.');
    }
    return _GlbDocument(
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(jsonBytes).trimRight()) as Map,
      ),
      Uint8List.fromList(binBytes),
    );
  }

  final Map<String, Object?> json;
  final Uint8List bin;

  Uint8List toBytes() {
    final jsonPayload = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final jsonPadding = (4 - jsonPayload.length % 4) % 4;
    final binPadding = (4 - bin.length % 4) % 4;
    final jsonLength = jsonPayload.length + jsonPadding;
    final binLength = bin.length + binPadding;
    final totalLength = 12 + 8 + jsonLength + 8 + binLength;
    final output = Uint8List(totalLength);
    final data = ByteData.sublistView(output);
    data.setUint32(0, _glbMagic, Endian.little);
    data.setUint32(4, 2, Endian.little);
    data.setUint32(8, totalLength, Endian.little);
    data.setUint32(12, jsonLength, Endian.little);
    data.setUint32(16, _jsonChunkType, Endian.little);
    output.setRange(20, 20 + jsonPayload.length, jsonPayload);
    output.fillRange(
      20 + jsonPayload.length,
      20 + jsonLength,
      0x20,
    );
    final binHeader = 20 + jsonLength;
    data.setUint32(binHeader, binLength, Endian.little);
    data.setUint32(binHeader + 4, _binChunkType, Endian.little);
    output.setRange(binHeader + 8, binHeader + 8 + bin.length, bin);
    return output;
  }
}

final class _OptimizationProfile {
  const _OptimizationProfile(this.name, this.images);

  factory _OptimizationProfile.named(String name) => switch (name) {
        'balanced' => const _OptimizationProfile('balanced', {
            0: _ImageSpec(512, 'uastc', 2),
            1: _ImageSpec(512, 'uastc', 2, normalMap: true),
            2: _ImageSpec(1024, 'uastc', 2),
            3: _ImageSpec(512, 'uastc', 2),
            4: _ImageSpec(512, 'uastc', 2, normalMap: true),
            5: _ImageSpec(1024, 'uastc', 2),
          }),
        'aggressive' => const _OptimizationProfile('aggressive', {
            0: _ImageSpec(256, 'etc1s', 160),
            1: _ImageSpec(256, 'etc1s', 160, normalMap: true),
            2: _ImageSpec(512, 'etc1s', 180),
            3: _ImageSpec(256, 'etc1s', 160),
            4: _ImageSpec(256, 'etc1s', 160, normalMap: true),
            5: _ImageSpec(512, 'etc1s', 180),
          }),
        _ => throw ArgumentError.value(name, 'profile', 'Unknown profile'),
      };

  final String name;
  final Map<int, _ImageSpec> images;
}

final class _ImageSpec {
  const _ImageSpec(
    this.size,
    this.encoding,
    this.quality, {
    this.normalMap = false,
  });

  final int size;
  final String encoding;
  final int quality;
  final bool normalMap;
}

final class _OptimizedImage {
  const _OptimizedImage({required this.name, required this.bytes});

  final String? name;
  final Uint8List bytes;
}

final class _Options {
  const _Options({
    required this.input,
    required this.output,
    required this.profile,
    required this.toktx,
    required this.toktxVersion,
    required this.reuseImagesFrom,
    required this.dpr,
    required this.heroWidth,
    required this.heroHeight,
  });

  factory _Options.parse(List<String> arguments) {
    String requiredValue(String name) {
      final prefix = '--$name=';
      for (final argument in arguments) {
        if (argument.startsWith(prefix)) {
          return argument.substring(prefix.length);
        }
      }
      throw ArgumentError('Missing $prefix...');
    }

    double optionalDouble(String name, double fallback) =>
        double.tryParse(_optionalValue(arguments, name) ?? '') ?? fallback;

    final reuseImagesFrom = _optionalValue(arguments, 'reuse-images-from');
    final toktx = _optionalValue(arguments, 'toktx');
    var toktxVersion = 'not used; existing KTX2 images reused';
    if (reuseImagesFrom == null) {
      if (toktx == null) throw ArgumentError('Missing --toktx=...');
      if (!File(toktx).existsSync()) {
        throw ArgumentError.value(toktx, 'toktx', 'Executable does not exist');
      }
      final version = Process.runSync(toktx, const ['--version']);
      if (version.exitCode != 0) {
        throw StateError('Unable to execute toktx: ${version.stderr}');
      }
      toktxVersion = '${version.stdout}${version.stderr}'.trim();
    }
    return _Options(
      input: requiredValue('input'),
      output: requiredValue('output'),
      profile: requiredValue('profile'),
      toktx: toktx,
      toktxVersion: toktxVersion,
      reuseImagesFrom: reuseImagesFrom,
      dpr: optionalDouble('dpr', 3),
      heroWidth: optionalDouble('hero-width', 235),
      heroHeight: optionalDouble('hero-height', 387),
    );
  }

  final String input;
  final String output;
  final String profile;
  final String? toktx;
  final String toktxVersion;
  final String? reuseImagesFrom;
  final double dpr;
  final double heroWidth;
  final double heroHeight;
}

String? _optionalValue(List<String> arguments, String name) {
  final prefix = '--$name=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) return argument.substring(prefix.length);
  }
  return null;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<Map<String, Object?>> _mapList(Object? value) => _list(value)
    .whereType<Map>()
    .map((item) => _deepCopyMap(Map<String, Object?>.from(item)))
    .toList(growable: false);

Map<String, Object?>? _map(Object? value) =>
    value is Map ? _deepCopyMap(Map<String, Object?>.from(value)) : null;

List<String> _stringList(Object? value) =>
    _list(value).whereType<String>().toList(growable: false);

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

Map<String, Object?> _deepCopyMap(Map<String, Object?> source) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(source)) as Map);
