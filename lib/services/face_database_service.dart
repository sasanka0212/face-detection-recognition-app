import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/face_record.dart';

class FaceDatabaseService {
  FaceDatabaseService._internal();

  static final FaceDatabaseService instance = FaceDatabaseService._internal();

  factory FaceDatabaseService() {
    return instance;
  }

  Database? _db;

  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }

    _db = await initialize();

    return _db!;
  }

  Future<Database> initialize() async {
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

    return _db!;
  }

  Future<void> saveFace(String name, List<double> embedding) async {
    await _db!.insert('faces', {
      'name': name,
      'embedding': jsonEncode(embedding),
    });
  }

  Future<List<FaceRecord>> getAllFaces() async {
    final rows = await _db!.query('faces');

    return rows.map((row) {
      return FaceRecord(
        id: row['id'] as int,
        name: row['name'] as String,
        embedding: (jsonDecode(row['embedding'] as String) as List)
            .map((e) => (e as num).toDouble())
            .toList(),
      );
    }).toList();
  }

  Future<void> deleteFace(String name) async {
    await _db!.delete('faces', where: 'name = ?', whereArgs: [name]);
  }

  Future<void> exportDb() async {
    final dbPath = await getDatabasesPath();

    final source = File(join(dbPath, 'faces.db'));

    final destination = File('/storage/emulated/0/Download/faces.db');

    await source.copy(destination.path);

    //print('db path: ${destination.path}');
  }

  Future<void> close() async {
    final db = await database;

    await db.close();

    _db = null;
  }
}
