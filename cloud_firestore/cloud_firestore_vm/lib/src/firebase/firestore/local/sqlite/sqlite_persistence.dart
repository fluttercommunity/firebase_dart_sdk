// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

library sqlite_persistence;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/index_range.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/index_cursor.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/reference_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/stats_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/types.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;
import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:semaphore/semaphore.dart';

part 'sqlite_collection_index.dart';
part 'sqlite_index_manager.dart';
part 'sqlite_lru_reference_delegate.dart';
part 'sqlite_mutation_queue.dart';
part 'sqlite_query_cache.dart';
part 'sqlite_remote_document_cache.dart';
part 'sqlite_schema.dart';

/// A SQLite-backed instance of Persistence.
///
/// In addition to implementations of the methods in the Persistence interface, also contains helper
/// routines that make dealing with SQLite much more pleasant.
class SQLitePersistence extends Persistence {
  SQLitePersistence._(this.serializer, this.openDatabase, this.databaseName,
      StatsCollector statsCollector)
      : _statsCollector = statsCollector ?? StatsCollector.noOp,
        _semaphore = GlobalSemaphore() {
    indexManager = SqliteIndexManager(this);
  }

  static const String tag = 'SQLitePersistence';

  final OpenDatabase openDatabase;
  final String databaseName;
  final LocalSerializer serializer;
  final StatsCollector _statsCollector;
  final Semaphore _semaphore;

  Database _db;

  @override
  bool started = false;

  @override
  SQLiteQueryCache queryCache;

  @override
  SqliteIndexManager indexManager;

  @override
  SQLiteRemoteDocumentCache remoteDocumentCache;

  @override
  SQLiteLruReferenceDelegate referenceDelegate;

  Future<int> get byteSize async {
    final int pageSize = await getPageSize();
    final int pageCount = await getPageCount();
    return pageCount * pageSize;
  }

  /// Gets the page size of the database. Typically 4096.
  ///
  /// @see https://www.sqlite.org/pragma.html#pragma_page_size
  Future<int> getPageSize() async {
    return (await _db.query('PRAGMA page_size'))[0].values.first;
  }

  /// Gets the number of pages in the database file. Multiplying this with the
  /// page size yields the approximate size of the database on disk (including
  /// the WAL, if relevant).
  ///
  /// @see https://www.sqlite.org/pragma.html#pragma_page_count.
  Future<int> getPageCount() async {
    return (await _db.query('PRAGMA page_count'))[0].values.first;
  }

  static Future<SQLitePersistence> create(
      String persistenceKey,
      DatabaseId databaseId,
      LocalSerializer serializer,
      OpenDatabase openDatabase,
      LruGarbageCollectorParams params,
      [StatsCollector statsCollector = StatsCollector.noOp]) async {
    final String databaseName = sDatabaseName(persistenceKey, databaseId);

    final SQLitePersistence persistence = SQLitePersistence._(
        serializer, openDatabase, databaseName, statsCollector);

    final SQLiteQueryCache queryCache =
        SQLiteQueryCache(persistence, serializer);
    final SQLiteRemoteDocumentCache remoteDocumentCache =
        SQLiteRemoteDocumentCache(persistence, serializer, statsCollector);
    final SQLiteLruReferenceDelegate referenceDelegate =
        SQLiteLruReferenceDelegate(persistence, params);

    return persistence
      ..queryCache = queryCache
      ..remoteDocumentCache = remoteDocumentCache
      ..referenceDelegate = referenceDelegate;
  }

  /// Creates the database name that is used to identify the database to be used with a Firestore instance. Note that
  /// this needs to stay stable across releases. The database is uniquely identified by a persistence key - usually the
  /// Firebase app name - and a DatabaseId (project and database).
  ///
  /// Format is [firestore.{persistence-key}.{project-id}.{database-id}].
  @visibleForTesting
  static String sDatabaseName(String persistenceKey, DatabaseId databaseId) {
    return 'firestore.'
        '${Uri.encodeQueryComponent(persistenceKey)}.'
        '${Uri.encodeQueryComponent(databaseId.projectId)}.'
        '${Uri.encodeQueryComponent(databaseId.databaseId)}';
  }

  @override
  Future<void> start() async {
    await _semaphore.acquire();
    Log.d(tag, 'Starting SQLite persistance');
    hardAssert(!started, 'SQLitePersistence double-started!');
    _db = await _openDb(databaseName, openDatabase);
    await queryCache.start();
    started = true;
    referenceDelegate.start(queryCache.highestListenSequenceNumber);
    _semaphore.release();
  }

  @override
  Future<void> shutdown() async {
    await _semaphore.acquire();
    Log.d(tag, 'Shutingdown SQLite persistance');
    hardAssert(started, 'SQLitePersistence shutdown without start!');

    started = false;
    _db.close();
    _db = null;
    _semaphore.release();
  }

  @visibleForTesting
  Database get database => _db;

  @override
  MutationQueue getMutationQueue(User user) {
    return SQLiteMutationQueue(this, serializer, _statsCollector, user);
  }

  @override
  Future<void> runTransaction(
      String action, Transaction<void> operation) async {
    return runTransactionAndReturn(action, operation);
  }

  @override
  Future<T> runTransactionAndReturn<T>(
      String action, Transaction<T> operation) async {
    await _semaphore.acquire();
    Log.d(tag, 'Starting transaction: $action');

    try {
      referenceDelegate.onTransactionStarted();
      await _db.execute('BEGIN;');
      final T result = await operation();
      await _db.execute('COMMIT;');
      await referenceDelegate.onTransactionCommitted();
      _semaphore.release();
      return result;
    } catch (e) {
      await _db.execute('ROLLBACK;');
      _semaphore.release();
      rethrow;
    }
  }

  /// Execute the given non-query SQL statement.
  Future<void> execute(String statement, [List<Object> args]) {
    return _db.execute(statement, args);
  }

  Future<List<Map<String, dynamic>>> query(String statement,
      [List<dynamic> args]) {
    return _db.query(statement, args);
  }

  Future<int> delete(String statement, [List<dynamic> args]) {
    return _db.delete(statement, args);
  }

  /// Configures database connections just the way we like them, delegating to SQLiteSchema to actually do the work of
  /// migration.
  ///
  /// The order of events when opening a new connection is as follows:
  ///   * New connection
  ///   * onConfigure
  ///   * onCreate / onUpgrade (optional; if version already matches these aren't called)
  ///   * onOpen
  ///
  /// This attempts to obtain exclusive access to the database and attempts to do so as early as possible.
  /// ^^^ todo: this breaks flutter hot reload
  static Future<Database> _openDb(
      String databaseName, OpenDatabase openDatabase) async {
    bool configured = false;

    /// Ensures that onConfigure has been called. This should be called first from all methods.
    Future<void> ensureConfigured(Database db) async {
      if (!configured) {
        configured = true;
        // todo: this breaks flutter hot reload
        // await db.query('PRAGMA locking_mode = EXCLUSIVE;');
      }
    }

    final Database db = await openDatabase(
      databaseName,
      version: SQLiteSchema.version,
      onConfigure: ensureConfigured,
      onCreate: (Database db, int version) async {
        await ensureConfigured(db);
        await SQLiteSchema(db).runMigrations(0);
      },
      onUpgrade: (Database db, int fromVersion, int toVersion) async {
        await ensureConfigured(db);
        await SQLiteSchema(db).runMigrations(fromVersion);
      },
      onDowngrade: (Database db, int fromVersion, int toVersion) async {
        await ensureConfigured(db);

        // For now, we can safely do nothing.
        //
        // The only case that's possible at this point would be to downgrade from version 1 (present
        // in our first released version) to 0 (uninstalled). Nobody would want us to just wipe the
        // data so instead we just keep it around in the hope that they'll upgrade again :-).
        //
        // Note that if you uninstall a Firestore-based app, the database goes away completely. The
        // downgrade-then-upgrade case can only happen in very limited circumstances.
        //
        // We'll have to revisit this once we ship a migration past version 1, but this will
        // definitely be good enough for our initial launch.
      },
      onOpen: (Database db) async => ensureConfigured(db),
    );

    return db;
  }
}

/// Encapsulates a query whose parameter list is so long that it might exceed SQLite limit.
///
/// SQLite limits maximum number of host parameters to 999 (see https://www.sqlite.org/limits.html). This class wraps
/// most of the messy details of splitting a large query into several smaller ones.
///
/// The class is configured to contain a "template" for each subquery:
///   * head -- the beginning of the query, will be the same for each subquery
///   * tail -- the end of the query, also the same for each subquery
///
/// Then the host parameters will be inserted in-between head and tail; if there are too many arguments for a single
/// query, several subqueries will be issued. Each subquery which will have the following form:
///
/// [head][an auto-generated comma-separated list of '?' placeholders][_tail]
///
/// To use this class, keep calling [performNextSubquery], which will issue the next subquery, as long as
/// [hasMoreSubqueries] returns true. Note that if the parameter list is empty, not even a single query will be issued.
///
/// For example, imagine for demonstration purposes that the limit were 2, and the [LongQuery] was created like this:
///
/// ```dart
///   final List<String> args = <String>['foo', 'bar', 'baz', 'spam', 'eggs'];
///   final LongQuery longQuery = LongQuery(
///     db,
///     'SELECT name WHERE id in (',
///     args,
///     ')',
///   );
/// ```
///
/// Assuming limit of 2, this query will issue three subqueries:
///
/// ```dart
///   await longQuery.performNextSubquery(); // SELECT name WHERE id in (?, ?) [foo, bar]
///   await longQuery.performNextSubquery(); // SELECT name WHERE id in (?, ?) [baz, spam]
///   await longQuery.performNextSubquery(); // SELECT name WHERE id in (?) [eggs]
/// ```
class LongQuery {
  /// Creates a new [LongQuery] with parameters that describe a template for creating each subquery.
  ///
  /// If [argsHead] is provided, it should contain the parameters that will be reissued in each subquery, i.e.
  /// subqueries take the form:
  ///
  /// [_head][_argsHead][an auto-generated comma-separated list of '?' placeholders][_tail]
  LongQuery(this._db, this._head, List<dynamic> argsHead,
      List<dynamic> argsIter, this._tail)
      : _argsIter = argsIter,
        _argsHead = argsHead ?? <dynamic>[],
        _subqueriesPerformed = 0;

  final SQLitePersistence _db;

  // The non-changing beginning of each subquery.
  final String _head;

  // The non-changing end of each subquery.
  final String _tail;

  // Arguments that will be prepended in each subquery before the main argument list.
  final List<Object> _argsHead;

  int _subqueriesPerformed;

  final List<Object> _argsIter;

  // Limit for the number of host parameters beyond which a query will be split into several subqueries. Deliberately
  // set way below 999 as a safety measure because this class doesn't attempt to check for placeholders in the query
  // [head]; if it only relied on the number of placeholders it itself generates, in that situation it would still
  // exceed the SQLite limit.
  static const int _limit = 900;

  int j = 0;

  /// Whether [performNextSubquery] can be called.
  bool get hasMoreSubqueries => j < _argsIter.length;

  /// Performs the next subquery
  Future<List<Map<String, dynamic>>> performNextSubquery() async {
    ++_subqueriesPerformed;

    final List<Object> subqueryArgs = List<Object>.from(_argsHead);
    final StringBuffer placeholdersBuilder = StringBuffer();

    for (int i = 0;
        j < _argsIter.length && i < _limit - _argsHead.length;
        i++) {
      if (i > 0) {
        placeholdersBuilder.write(', ');
      }
      placeholdersBuilder.write('?');

      subqueryArgs.add(_argsIter[j]);
      j++;
    }

    return _db.query('$_head$placeholdersBuilder$_tail', subqueryArgs);
  }

  /// How many subqueries were performed.
  int get subqueriesPerformed => _subqueriesPerformed;
}
