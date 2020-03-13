// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:async';
import 'dart:io';

typedef OpenDatabase = Future<Database> Function(String path,
    {int version,
    OnConfigure onConfigure,
    OnCreate onCreate,
    OnVersionChange onUpgrade,
    OnVersionChange onDowngrade,
    OnOpen onOpen});

typedef OnVersionChange = Future<void> Function(
    Database db, int oldVersion, int newVersion);
typedef OnCreate = Future<void> Function(Database db, int version);
typedef OnOpen = Future<void> Function(Database db);
typedef OnConfigure = Future<void> Function(Database db);

abstract class Database {
  File get file;

  /// Runs SQLite statement without return values
  Future<void> execute(String statement, [List<dynamic> arguments]);

  /// SELECT query
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<dynamic> arguments]);

  /// DELETE query
  /// Returns the number of changes made
  Future<int> delete(String statement, [List<dynamic> arguments]);

  void close();
}

enum ConflictAlgorithm {
  /// When a constraint violation occurs, an immediate ROLLBACK occurs, thus ending the current transaction, and the
  /// command aborts with a return code of SQLITE_CONSTRAINT. If no transaction is active (other than the implied
  /// transaction that is created on every command) then this algorithm works the same as ABORT.
  rollback,

  /// When a constraint violation occurs,no ROLLBACK is executed so changes from prior commands within the same
  /// transaction are preserved. This is the default behavior.
  abort,

  /// When a constraint violation occurs, the command aborts with a return code SQLITE_CONSTRAINT. But any changes to
  /// the database that the command made prior to encountering the constraint violation are preserved and are not backed
  /// out.
  fail,

  /// When a constraint violation occurs, the one row that contains the constraint violation is not inserted or changed.
  /// But the command continues executing normally. Other rows before and after the row that contained the constraint
  /// violation continue to be inserted or updated normally. No error is returned.
  ignore,

  /// When a UNIQUE constraint violation occurs, the pre-existing rows that are causing the constraint violation are
  /// removed prior to inserting or updating the current row. Thus the insert or update always occurs. The command
  /// continues executing normally. No error is returned. If a NOT NULL constraint violation occurs, the NULL value is
  /// replaced by the default value for that column. If the column has no default value, then the ABORT algorithm is
  /// used. If a CHECK constraint violation occurs then the IGNORE algorithm is used. When this conflict resolution
  /// strategy deletes rows in order to satisfy a constraint, it does not invoke delete triggers on those rows. This
  /// behavior might change in a future release.
  replace,
}
