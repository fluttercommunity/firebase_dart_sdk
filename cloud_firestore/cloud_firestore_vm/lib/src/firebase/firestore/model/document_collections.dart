// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';

/// Provides static helpers around document collections.
class DocumentCollections {
  /// Returns an empty, immutable document map
  static ImmutableSortedMap<DocumentKey, Document> emptyDocumentMap() {
    return ImmutableSortedMap<DocumentKey, Document>.emptyMap(
        DocumentKey.comparator);
  }

  /// Returns an empty, immutable 'maybe' document map
  static ImmutableSortedMap<DocumentKey, MaybeDocument>
      emptyMaybeDocumentMap() {
    return ImmutableSortedMap<DocumentKey, MaybeDocument>.emptyMap(
        DocumentKey.comparator);
  }

  /// Returns an empty, immutable versions map
  static ImmutableSortedMap<DocumentKey, SnapshotVersion> emptyVersionMap() {
    return ImmutableSortedMap<DocumentKey, SnapshotVersion>.emptyMap(
        DocumentKey.comparator);
  }
}
