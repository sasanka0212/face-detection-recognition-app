import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/face_record.dart';

class FaceDatabaseService {
  Database? _db;

  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();

    _db = await openDatabase(
      join(dbPath, 'faces.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE faces(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            embedding TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> saveFace(
    String name,
    List<double> embedding,
  ) async {

    await _db!.insert(
      'faces',
      {
        'name': name,
        'embedding': jsonEncode(
          embedding,
        ),
      },
    );
  }

  Future<List<FaceRecord>> getAllFaces() async {
    final rows =
        await _db!.query(
          'faces',
        );

    return rows.map((row) {

      return FaceRecord(
        id: row['id'] as int,
        name: row['name'] as String,
        embedding:
            (jsonDecode(
              row['embedding'] as String,
            ) as List)
            .map(
              (e) => (e as num).toDouble(),
            )
            .toList(),
      );

    }).toList();
  }

  Future<void> deleteFace(
    String name,
  ) async {

    await _db!.delete(
      'faces',
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  Future<void> exportDb() async {
    final dbPath = await getDatabasesPath();

    final source = File(
      join(dbPath, 'faces.db'),
    );

    final destination = File(
      '/storage/emulated/0/Download/faces.db',
    );

    await source.copy(destination.path);

    print('db path: ${destination.path}');
  }
}