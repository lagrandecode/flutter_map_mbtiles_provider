import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Simple Coords class to hold x, y, and z values for tiles
class Coords<T> {
  final T x, y, z;

  Coords(this.x, this.y, this.z);

  @override
  String toString() => 'Coords(x: $x, y: $y, z: $z)';
}

class MBTilesImageProvider extends TileProvider {
  final String asset;
  final File mbtilesFile;

  Future<Database> database;
  Database _loadedDb;
  bool isDisposed = false;

  MBTilesImageProvider._({this.asset, this.mbtilesFile}) {
    database = _loadMBTilesDatabase();
  }

  factory MBTilesImageProvider.fromAsset(String asset) => MBTilesImageProvider._(asset: asset);

  factory MBTilesImageProvider.fromFile(File mbtilesFile) => MBTilesImageProvider._(mbtilesFile: mbtilesFile);

  Future<Database> _loadMBTilesDatabase() async {
    if (_loadedDb == null) {
      var file = mbtilesFile ?? await copyFileFromAssets();

      _loadedDb = await openDatabase(file.path);

      if (isDisposed) {
        await _loadedDb.close();
        _loadedDb = null;
        throw Exception('Tileprovider is already disposed');
      }
    }

    return _loadedDb;
  }

  @override
  void dispose() {
    if (_loadedDb != null) {
      _loadedDb.close();
      _loadedDb = null;
    }
    isDisposed = true;
  }

  Future<File> copyFileFromAssets() async {
    var tempDir = await getTemporaryDirectory();
    var filename = asset.split('/').last;
    var file = File('${tempDir.path}/$filename');

    var data = await rootBundle.load(asset);
    file.writeAsBytesSync(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    return file;
  }

  @override
  ImageProvider getImage(Coords<num> coords, TileLayerOptions options) {
    var x = coords.x.round();
    var y = options.tms ? invertY(coords.y.round(), coords.z.round()) : coords.y.round();
    var z = coords.z.round();

    return MBTileImage(
      database,
      Coords<int>(x, y)..z = z,
      mbtilesFile?.path ?? asset,
    );
  }
}

class MBTileImage extends ImageProvider<MBTileImage> {
  final Future<Database> database;
  final Coords<int> coords;
  final String filePath;

  MBTileImage(this.database, this.coords, this.filePath);

  @override
  ImageStreamCompleter load(MBTileImage key, decode) {
    return MultiFrameImageStreamCompleter(
        codec: _loadAsync(key),
        scale: 1,
        informationCollector: () sync* {
          yield DiagnosticsProperty<ImageProvider>('Image provider', this);
          yield DiagnosticsProperty<ImageProvider>('Image key', key);
        });
  }

  Future<Codec> _loadAsync(MBTileImage key) async {
    assert(key == this);

    final db = await key.database;
    List<Map> result = await db.rawQuery('select tile_data from tiles '
        'where zoom_level = ${coords.z} AND '
        'tile_column = ${coords.x} AND '
        'tile_row = ${coords.y} limit 1');
    final Uint8List bytes = result.isNotEmpty ? result.first['tile_data'] : null;

    if (bytes == null) {
      return Future<Codec>.error('Failed to load tile for coords: $coords');
    }
    return await PaintingBinding.instance.instantiateImageCodec(bytes);
  }

  @override
  Future<MBTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  int get hashCode => coords.hashCode;

  @override
  bool operator ==(other) {
    return other is MBTileImage && coords == other.coords && filePath == other.filePath;
  }
}
//cccc
