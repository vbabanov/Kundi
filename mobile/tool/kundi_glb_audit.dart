import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _glbMagic = 0x46546c67;
const _jsonChunkType = 0x4e4f534a;
const _binChunkType = 0x004e4942;

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/kundi_glb_audit.dart <model.glb> '
      '[--json] [--dpr=3.0] [--hero-width=235] [--hero-height=387]',
    );
    exitCode = 64;
    return;
  }

  final path = arguments.first;
  final asJson = arguments.contains('--json');
  final dpr = _optionDouble(arguments, '--dpr', 3);
  final heroWidth = _optionDouble(arguments, '--hero-width', 235);
  final heroHeight = _optionDouble(arguments, '--hero-height', 387);
  final audit = auditGlb(
    File(path).readAsBytesSync(),
    path: path,
    dpr: dpr,
    heroWidth: heroWidth,
    heroHeight: heroHeight,
  );

  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(audit));
    return;
  }
  _printHuman(audit);
}

Map<String, Object?> auditGlb(
  Uint8List bytes, {
  required String path,
  required double dpr,
  required double heroWidth,
  required double heroHeight,
}) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 20 || data.getUint32(0, Endian.little) != _glbMagic) {
    throw const FormatException('Input is not a GLB file.');
  }
  final version = data.getUint32(4, Endian.little);
  final declaredLength = data.getUint32(8, Endian.little);
  if (version != 2 || declaredLength != bytes.length) {
    throw FormatException(
      'Unsupported or malformed GLB: version=$version '
      'declaredLength=$declaredLength actualLength=${bytes.length}',
    );
  }

  Uint8List? jsonBytes;
  Uint8List? binBytes;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    final end = start + chunkLength;
    if (end > bytes.length) {
      throw const FormatException('GLB chunk exceeds declared file length.');
    }
    final chunk = Uint8List.sublistView(bytes, start, end);
    if (chunkType == _jsonChunkType) {
      jsonBytes = chunk;
    } else if (chunkType == _binChunkType) {
      binBytes = chunk;
    }
    offset = end;
  }
  if (jsonBytes == null || binBytes == null) {
    throw const FormatException('GLB must contain JSON and BIN chunks.');
  }

  final jsonText = utf8.decode(jsonBytes).trimRight();
  final gltf = Map<String, Object?>.from(jsonDecode(jsonText) as Map);
  final accessors = _mapList(gltf['accessors']);
  final bufferViews = _mapList(gltf['bufferViews']);
  final meshes = _mapList(gltf['meshes']);
  final animations = _mapList(gltf['animations']);
  final skins = _mapList(gltf['skins']);
  final images = _mapList(gltf['images']);
  final textures = _mapList(gltf['textures']);
  final materials = _mapList(gltf['materials']);

  final geometryAccessors = <int>{};
  final indexAccessors = <int>{};
  final morphAccessors = <int>{};
  final animationAccessors = <int>{};
  final skinAccessors = <int>{};
  final morphNames = <String>{};
  var primitiveCount = 0;
  var vertexCount = 0;
  var indexCount = 0;
  var morphTargetSlots = 0;

  for (final mesh in meshes) {
    final targetNames = _stringList(_map(mesh['extras'])?['targetNames']);
    morphNames.addAll(targetNames);
    for (final primitive in _mapList(mesh['primitives'])) {
      primitiveCount++;
      final attributes = _map(primitive['attributes']) ?? const {};
      for (final value in attributes.values) {
        if (value is num) geometryAccessors.add(value.toInt());
      }
      final positionAccessor = attributes['POSITION'];
      if (positionAccessor is num) {
        vertexCount += _int(accessors[positionAccessor.toInt()]['count']);
      }
      final indices = primitive['indices'];
      if (indices is num) {
        final accessorIndex = indices.toInt();
        indexAccessors.add(accessorIndex);
        indexCount += _int(accessors[accessorIndex]['count']);
      }
      final targets = _mapList(primitive['targets']);
      morphTargetSlots += targets.length;
      for (final target in targets) {
        for (final value in target.values) {
          if (value is num) morphAccessors.add(value.toInt());
        }
      }
    }
  }

  final animationDetails = <Map<String, Object?>>[];
  for (var animationIndex = 0;
      animationIndex < animations.length;
      animationIndex++) {
    final animation = animations[animationIndex];
    final localAccessors = <int>{};
    for (final sampler in _mapList(animation['samplers'])) {
      for (final key in const ['input', 'output']) {
        final value = sampler[key];
        if (value is num) {
          localAccessors.add(value.toInt());
          animationAccessors.add(value.toInt());
        }
      }
    }
    animationDetails.add({
      'name': (animation['name'] as String?) ?? 'animation_$animationIndex',
      'channels': _mapList(animation['channels']).length,
      'logicalAccessorBytes': _logicalAccessorBytes(accessors, localAccessors),
      'bufferViewBytes': _bufferViewBytes(
        accessors,
        bufferViews,
        localAccessors,
      ),
    });
  }

  var jointCount = 0;
  for (final skin in skins) {
    jointCount += _list(skin['joints']).length;
    final inverseBindMatrices = skin['inverseBindMatrices'];
    if (inverseBindMatrices is num) {
      skinAccessors.add(inverseBindMatrices.toInt());
    }
  }

  final imageDetails = <Map<String, Object?>>[];
  var imageCompressedBytes = 0;
  var decodedRgbaBaseBytes = 0;
  var decodedRgbaMipBytes = 0;
  for (var imageIndex = 0; imageIndex < images.length; imageIndex++) {
    final image = images[imageIndex];
    final viewIndex = _int(image['bufferView'], fallback: -1);
    final mimeType = (image['mimeType'] as String?) ?? 'unknown';
    var compressedBytes = 0;
    var dimensions = const _ImageDimensions(0, 0, 'unknown');
    if (viewIndex >= 0 && viewIndex < bufferViews.length) {
      final view = bufferViews[viewIndex];
      final byteOffset = _int(view['byteOffset']);
      compressedBytes = _int(view['byteLength']);
      final imageBytes = Uint8List.sublistView(
        binBytes,
        byteOffset,
        byteOffset + compressedBytes,
      );
      dimensions = _imageDimensions(imageBytes, mimeType);
    }
    final rgbaBytes = dimensions.width * dimensions.height * 4;
    final rgbaMipBytes = rgbaBytes == 0 ? 0 : (rgbaBytes * 4 / 3).ceil();
    imageCompressedBytes += compressedBytes;
    decodedRgbaBaseBytes += rgbaBytes;
    decodedRgbaMipBytes += rgbaMipBytes;
    imageDetails.add({
      'index': imageIndex,
      'name': image['name'],
      'mimeType': mimeType,
      'format': dimensions.format,
      'width': dimensions.width,
      'height': dimensions.height,
      'compressedBytes': compressedBytes,
      'decodedRgbaBaseBytes': rgbaBytes,
      'decodedRgbaWithMipsBytes': rgbaMipBytes,
    });
  }

  final usedMaterialIndices = <int>{};
  final primitiveDetails = <Map<String, Object?>>[];
  for (final mesh in meshes) {
    var primitiveIndex = 0;
    for (final primitive in _mapList(mesh['primitives'])) {
      final material = primitive['material'];
      if (material is num) usedMaterialIndices.add(material.toInt());
      primitiveDetails.add({
        'mesh': mesh['name'],
        'primitive': primitiveIndex,
        'materialIndex': material,
        'materialName': material is num && material.toInt() < materials.length
            ? materials[material.toInt()]['name']
            : null,
      });
      primitiveIndex++;
    }
  }
  final allTextureIndices = <int>{};
  final materialDetails = <Map<String, Object?>>[];
  for (var materialIndex = 0;
      materialIndex < materials.length;
      materialIndex++) {
    final material = materials[materialIndex];
    final bindings = <Map<String, Object?>>[];
    _collectTextureBindings(material, '', bindings);
    for (final binding in bindings) {
      final textureIndex = _int(binding['textureIndex'], fallback: -1);
      if (textureIndex < 0 || textureIndex >= textures.length) continue;
      final texture = textures[textureIndex];
      final basis = _map(_map(texture['extensions'])?['KHR_texture_basisu']);
      final source = _int(basis?['source'] ?? texture['source'], fallback: -1);
      binding['sourceImageIndex'] = source;
      binding['sourceImageName'] =
          source >= 0 && source < images.length ? images[source]['name'] : null;
    }
    materialDetails.add({
      'index': materialIndex,
      'name': material['name'],
      'textureBindings': bindings,
    });
  }
  for (final material in materials) {
    _collectTextureIndices(material, allTextureIndices);
  }

  final renderTargets = <Map<String, Object?>>[];
  for (final scale in const [1.0, 0.75, 0.5]) {
    final width = math.max(1, (heroWidth * dpr * scale).round());
    final height = math.max(1, (heroHeight * dpr * scale).round());
    final pixels = width * height;
    renderTargets.add({
      'scale': scale,
      'physicalWidth': width,
      'physicalHeight': height,
      'singleColorDepthBytes': pixels * 8,
      'tripleColorPlusDepthBytes': pixels * 16,
    });
  }

  final extensionUsed = _stringList(gltf['extensionsUsed']);
  final extensionRequired = _stringList(gltf['extensionsRequired']);
  final geometryAll = <int>{...geometryAccessors, ...indexAccessors};

  return {
    'path': path,
    'fileBytes': bytes.length,
    'glb': {
      'version': version,
      'jsonChunkBytes': jsonBytes.length,
      'binChunkBytes': binBytes.length,
      'extensionsUsed': extensionUsed,
      'extensionsRequired': extensionRequired,
    },
    'scene': {
      'nodes': _mapList(gltf['nodes']).length,
      'scenes': _mapList(gltf['scenes']).length,
      'meshes': meshes.length,
      'primitives': primitiveCount,
      'vertices': vertexCount,
      'indices': indexCount,
      'skins': skins.length,
      'joints': jointCount,
      'materials': materials.length,
      'usedMaterials': usedMaterialIndices.length,
      'textures': textures.length,
      'referencedTextures': allTextureIndices.length,
      'images': images.length,
      'primitivesByMaterial': primitiveDetails,
      'materialTextureBindings': materialDetails,
    },
    'geometry': {
      'logicalAccessorBytes': _logicalAccessorBytes(accessors, geometryAll),
      'bufferViewBytes': _bufferViewBytes(accessors, bufferViews, geometryAll),
      'vertexLogicalBytes': _logicalAccessorBytes(accessors, geometryAccessors),
      'indexLogicalBytes': _logicalAccessorBytes(accessors, indexAccessors),
      'skinLogicalBytes': _logicalAccessorBytes(accessors, skinAccessors),
    },
    'morphTargets': {
      'namedTargetCount': morphNames.length,
      'targetSlotsAcrossPrimitives': morphTargetSlots,
      'names': morphNames.toList()..sort(),
      'logicalAccessorBytes': _logicalAccessorBytes(accessors, morphAccessors),
      'bufferViewBytes': _bufferViewBytes(
        accessors,
        bufferViews,
        morphAccessors,
      ),
    },
    'animations': {
      'count': animations.length,
      'logicalAccessorBytes': _logicalAccessorBytes(
        accessors,
        animationAccessors,
      ),
      'bufferViewBytes': _bufferViewBytes(
        accessors,
        bufferViews,
        animationAccessors,
      ),
      'clips': animationDetails,
    },
    'textures': {
      'compressedImageBytes': imageCompressedBytes,
      'decodedRgbaBaseBytes': decodedRgbaBaseBytes,
      'decodedRgbaWithMipsBytes': decodedRgbaMipBytes,
      'images': imageDetails,
    },
    'cpuSourceBuffers': {
      'fileReadBytes': bytes.length,
      'directGlbBufferBytes': bytes.length,
      'temporarySourcePeakBytes': bytes.length * 2,
      'releaseSourceDataRequired': true,
    },
    'renderTargets': {
      'heroLogicalWidth': heroWidth,
      'heroLogicalHeight': heroHeight,
      'devicePixelRatio': dpr,
      'estimates': renderTargets,
      'note': 'Range is RGBA8+depth for one color buffer through '
          'triple-buffered color+depth; driver overhead is excluded.',
    },
  };
}

void _printHuman(Map<String, Object?> audit) {
  stdout.writeln('Kundi GLB audit: ${audit['path']}');
  stdout.writeln('fileBytes: ${audit['fileBytes']}');
  for (final section in const [
    'glb',
    'scene',
    'geometry',
    'morphTargets',
    'animations',
    'textures',
    'cpuSourceBuffers',
    'renderTargets',
  ]) {
    stdout.writeln('\n[$section]');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(audit[section]));
  }
}

double _optionDouble(List<String> arguments, String name, double fallback) {
  final prefix = '$name=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return double.tryParse(argument.substring(prefix.length)) ?? fallback;
    }
  }
  return fallback;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<Map<String, Object?>> _mapList(Object? value) => _list(
      value,
    ).whereType<Map>().map(Map<String, Object?>.from).toList(growable: false);

Map<String, Object?>? _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

List<String> _stringList(Object? value) =>
    _list(value).whereType<String>().toList(growable: false);

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

int _logicalAccessorBytes(
  List<Map<String, Object?>> accessors,
  Set<int> indices,
) {
  var total = 0;
  for (final index in indices) {
    if (index < 0 || index >= accessors.length) continue;
    final accessor = accessors[index];
    total += _int(accessor['count']) *
        _componentCount(accessor['type'] as String?) *
        _componentBytes(_int(accessor['componentType']));
  }
  return total;
}

int _bufferViewBytes(
  List<Map<String, Object?>> accessors,
  List<Map<String, Object?>> bufferViews,
  Set<int> accessorIndices,
) {
  final views = <int>{};
  for (final index in accessorIndices) {
    if (index < 0 || index >= accessors.length) continue;
    final accessor = accessors[index];
    final view = accessor['bufferView'];
    if (view is num) views.add(view.toInt());
    final sparse = _map(accessor['sparse']);
    final indicesView = _map(sparse?['indices'])?['bufferView'];
    final valuesView = _map(sparse?['values'])?['bufferView'];
    if (indicesView is num) views.add(indicesView.toInt());
    if (valuesView is num) views.add(valuesView.toInt());
  }
  return views.fold<int>(0, (sum, index) {
    if (index < 0 || index >= bufferViews.length) return sum;
    return sum + _int(bufferViews[index]['byteLength']);
  });
}

int _componentBytes(int componentType) => switch (componentType) {
      5120 || 5121 => 1,
      5122 || 5123 => 2,
      5125 || 5126 => 4,
      _ => 0,
    };

int _componentCount(String? type) => switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' || 'MAT2' => 4,
      'MAT3' => 9,
      'MAT4' => 16,
      _ => 0,
    };

void _collectTextureIndices(Object? value, Set<int> out) {
  if (value is Map) {
    final index = value['index'];
    if (index is num) out.add(index.toInt());
    for (final child in value.values) {
      _collectTextureIndices(child, out);
    }
  } else if (value is List) {
    for (final child in value) {
      _collectTextureIndices(child, out);
    }
  }
}

void _collectTextureBindings(
  Object? value,
  String path,
  List<Map<String, Object?>> out,
) {
  if (value is Map) {
    final index = value['index'];
    if (index is num) {
      out.add({'slot': path, 'textureIndex': index.toInt()});
    }
    for (final entry in value.entries) {
      final nextPath = path.isEmpty ? '${entry.key}' : '$path.${entry.key}';
      _collectTextureBindings(entry.value, nextPath, out);
    }
  } else if (value is List) {
    for (var index = 0; index < value.length; index++) {
      _collectTextureBindings(value[index], '$path[$index]', out);
    }
  }
}

_ImageDimensions _imageDimensions(Uint8List bytes, String mimeType) {
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    final data = ByteData.sublistView(bytes);
    return _ImageDimensions(
      data.getUint32(16, Endian.big),
      data.getUint32(20, Endian.big),
      'png',
    );
  }
  if (bytes.length >= 12 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    var offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xff) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xd8 || marker == 0xd9) {
        offset += 2;
        continue;
      }
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (length < 2 || offset + 2 + length > bytes.length) break;
      if ((marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf)) {
        return _ImageDimensions(
          (bytes[offset + 7] << 8) | bytes[offset + 8],
          (bytes[offset + 5] << 8) | bytes[offset + 6],
          'jpeg',
        );
      }
      offset += 2 + length;
    }
  }
  const ktx2Identifier = <int>[
    0xab,
    0x4b,
    0x54,
    0x58,
    0x20,
    0x32,
    0x30,
    0xbb,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ];
  if (bytes.length >= 28 &&
      List<int>.generate(12, (index) => bytes[index]).join(',') ==
          ktx2Identifier.join(',')) {
    final data = ByteData.sublistView(bytes);
    return _ImageDimensions(
      data.getUint32(20, Endian.little),
      data.getUint32(24, Endian.little),
      'ktx2',
    );
  }
  return _ImageDimensions(0, 0, mimeType);
}

final class _ImageDimensions {
  const _ImageDimensions(this.width, this.height, this.format);

  final int width;
  final int height;
  final String format;
}
