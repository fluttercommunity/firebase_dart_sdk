// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart' as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:rxdart/rxdart.dart';

/// A [DocumentReference] refers to a document location in a Cloud Firestore database and can be used to write, read, or
/// listen to the location. There may or may not exist a document at the referenced location. A [DocumentReference] can
/// also be used to create a [CollectionReference] to a subcollection.
///
/// **Subclassing Note**: Cloud Firestore classes are not meant to be subclassed except for use in test mocks.
/// Subclassing is not supported in production code and new SDK releases may break code that does so.
class DocumentReference {
  // TODO(long1eu): We should checkNotNull(firestore), but tests are currently cheating and setting it to null.
  DocumentReference(this.key, this.firestore) : assert(key != null);

  factory DocumentReference.forPath(ResourcePath path, Firestore firestore) {
    if (path.length.remainder(2) != 0) {
      throw ArgumentError('Invalid document reference. Document references must have an even number of segments, but '
          '${path.canonicalString} has ${path.length}');
    }

    return DocumentReference(DocumentKey.fromPath(path), firestore);
  }

  final DocumentKey key;

  /// Gets the Cloud Firestore instance associated with this document reference.
  final Firestore firestore;

  String get id => key.path.last;

  /// Gets a [CollectionReference] to the collection that contains this document.
  ///
  /// Returns the [CollectionReference] that contains this document.
  CollectionReference get parent {
    return CollectionReference(key.path.popLast(), firestore);
  }

  /// Gets the path of this document (relative to the root of the database) as a slash-separated  string.
  ///
  /// Returns the path of this document.
  String get path => key.path.canonicalString;

  /// Gets a [CollectionReference] instance that refers to the subcollection at the specified path relative to this
  /// document.
  ///
  /// [collectionPath] a slash-separated relative path to a subcollection.
  ///
  /// Returns the [CollectionReference] instance.
  CollectionReference collection(String collectionPath) {
    checkNotNull(collectionPath, 'Provided collection path must not be null.');
    return CollectionReference(key.path.appendField(ResourcePath.fromString(collectionPath)), firestore);
  }

  /// Writes to the document referred to by this DocumentReference. If the document does not yet exist, it will be
  /// created. If you pass [SetOptions], the provided data can be merged into an existing document.
  ///
  /// [data] a map of the fields and values for the document.
  /// [options] an object to configure the set behavior.
  ///
  /// Returns a Future that will be resolved when the write finishes.
  Future<void> set(Map<String, Object> data, [SetOptions options]) async {
    options ??= SetOptions.overwrite;
    checkNotNull(data, 'Provided data must not be null.');
    checkNotNull(options, 'Provided options must not be null.');
    final UserDataParsedSetData parsed = options.merge
        ? firestore.userDataReader.parseMergeData(data, options.fieldMask)
        : firestore.userDataReader.parseSetData(data);

    await voidErrorTransformer(() => firestore.client.write(<Mutation>[parsed.toMutation(key, Precondition.none)]));
  }

  /// Updates fields in the document referred to by this [DocumentReference]. If no document exists yet, the update will
  /// fail.
  ///
  /// [data] a map of field/value pairs to update. Fields can contain dots to reference nested fields within the
  /// document.
  ///
  /// Returns a Future that will be resolved when the write finishes.
  Future<void> update(Map<String, Object> data) async {
    final UserDataParsedUpdateData parsedData = firestore.userDataReader.parseUpdateData(data);
    await voidErrorTransformer(() {
      return firestore.client.write(<Mutation>[parsedData.toMutation(key, Precondition(exists: true))]);
    });
  }

  /// Deletes the document referred to by this [DocumentReference].
  ///
  /// Returns a Future that will be resolved when the delete completes.
  Future<void> delete() {
    return voidErrorTransformer(() => firestore.client.write(<DeleteMutation>[DeleteMutation(key, Precondition.none)]));
  }

  /// Reads the document referenced by this [DocumentReference].
  ///
  /// By default, [get] attempts to provide up-to-date data when possible by waiting for data from the server, but it
  /// may return cached data or fail if you are offline and the server cannot be reached. This behavior can be altered
  /// via the [Source] parameter.
  ///
  /// [source] a value to configure the get behavior.
  ///
  /// Returns a Future that will be resolved with the contents of the [Document] at this [DocumentReference].
  Future<DocumentSnapshot> get([Source source]) async {
    source ??= Source.defaultSource;

    if (source == Source.cache) {
      final Document doc = await firestore.client.getDocumentFromLocalCache(key);
      final bool hasPendingWrites = doc != null && doc.hasLocalMutations;

      return DocumentSnapshot(
        firestore,
        key,
        doc,
        isFromCache: true,
        hasPendingWrites: hasPendingWrites,
      );
    } else {
      return _getViaSnapshotListener(source);
    }
  }

  Future<DocumentSnapshot> _getViaSnapshotListener(Source source) {
    return _getSnapshotsInternal(const ListenOptions.all()).map((DocumentSnapshot snapshot) {
      if (!snapshot.exists && snapshot.metadata.isFromCache) {
        // TODO(long1eu): Reconsider how to raise missing documents when offline.
        //  If we're online and the document doesn't exist then we set the result of the Future with a document with
        //  document.exists set to false. If we're offline however, we set the Error on the Task. Two options:
        //    1. Cache the negative response from the server so we can deliver that even when you're offline.
        //    2. Actually set the Error of the Task if the document doesn't exist when you are offline.
        throw FirestoreError('Failed to get document because the client is offline.', FirestoreErrorCode.unavailable);
      } else if (snapshot.exists && snapshot.metadata.isFromCache && source == Source.server) {
        throw FirestoreError(
            'Failed to get document from server. (However, this document does exist in the local cache. Run again '
            'without setting source to Source.SERVER to retrieve the cached document.)',
            FirestoreErrorCode.unavailable);
      } else {
        return snapshot;
      }
    }).first;
  }

  Stream<DocumentSnapshot> get snapshots {
    final ListenOptions options = _internalOptions(MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  Stream<DocumentSnapshot> getSnapshots([MetadataChanges changes]) {
    final ListenOptions options = _internalOptions(changes ?? MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  Stream<DocumentSnapshot> _getSnapshotsInternal(ListenOptions options) {
    final core.Query query = core.Query(key.path);

    return Stream<QueryStream>.fromFuture(firestore.client.listen(query, options))
        .flatMap((QueryStream it) => it)
        .map((ViewSnapshot snapshot) {
      hardAssert(snapshot.documents.length <= 1, 'Too many documents returned on a document query');
      final Document document = snapshot.documents.getDocument(key);

      if (document != null) {
        final bool hasPendingWrites = snapshot.mutatedKeys.contains(document.key);
        return DocumentSnapshot.fromDocument(
          firestore,
          document,
          isFromCache: snapshot.isFromCache,
          hasPendingWrites: hasPendingWrites,
        );
      } else {
        // We don't raise `hasPendingWrites` for deleted documents.
        const bool hasPendingWrites = false;
        return DocumentSnapshot.fromNoDocument(
          firestore,
          key,
          isFromCache: snapshot.isFromCache,
          hasPendingWrites: hasPendingWrites,
        );
      }
    });
  }

  /// Converts the  API [MetadataChanges] object to the internal options object.
  static ListenOptions _internalOptions(MetadataChanges metadataChanges) {
    return ListenOptions(
      includeDocumentMetadataChanges: metadataChanges == MetadataChanges.include,
      includeQueryMetadataChanges: metadataChanges == MetadataChanges.include,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentReference &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          firestore == other.firestore;

  @override
  int get hashCode => key.hashCode * 31 ^ firestore.hashCode * 31;
}
