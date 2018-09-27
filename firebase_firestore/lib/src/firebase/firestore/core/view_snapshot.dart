// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:collection/collection.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';

/// The possibly states a document can be in w.r.t syncing from local storage to
/// the backend.
enum ViewSnapshotSyncState {
  none,
  local,
  synced,
}

class ViewSnapshot {
  final Query query;
  final DocumentSet documents;
  final DocumentSet oldDocuments;
  final List<DocumentViewChange> changes;
  final bool isFromCache;
  final bool hasPendingWrites;
  final bool didSyncStateChange;

  ViewSnapshot(
    this.query,
    this.documents,
    this.oldDocuments,
    this.changes,
    this.isFromCache,
    this.hasPendingWrites,
    this.didSyncStateChange,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (other is ViewSnapshot && runtimeType == other.runtimeType) {
      return isFromCache == other.isFromCache &&
          hasPendingWrites == other.hasPendingWrites &&
          didSyncStateChange == other.didSyncStateChange &&
          query == other.query &&
          documents == other.documents &&
          oldDocuments == other.oldDocuments &&
          const DeepCollectionEquality().equals(changes, other.changes);
    }

    return false;
  }

  @override
  int get hashCode =>
      query.hashCode ^
      documents.hashCode ^
      oldDocuments.hashCode ^
      changes.hashCode ^
      isFromCache.hashCode ^
      hasPendingWrites.hashCode ^
      didSyncStateChange.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('query', query)
          ..add('documents', documents)
          ..add('oldDocuments', oldDocuments)
          ..add('changes', changes)
          ..add('isFromCache', isFromCache)
          ..add('hasPendingWrites', hasPendingWrites)
          ..add('didSyncStateChange', didSyncStateChange))
        .toString();
  }
}
