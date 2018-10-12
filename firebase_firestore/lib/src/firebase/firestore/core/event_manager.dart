// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/sync_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';

/// EventManager is responsible for mapping queries to query event listeners.
/// It handles "fan-out." (Identical queries will re-use the same watch on the
/// backend.)
class EventManager implements SyncEngineCallback {
  final SyncEngine syncEngine;

  final Map<Query, QueryListenersInfo> queries;

  OnlineState onlineState = OnlineState.unknown;

  EventManager(this.syncEngine) : this.queries = <Query, QueryListenersInfo>{} {
    syncEngine.callback = this;
  }

  /// Adds a query listener that will be called with new snapshots for the
  /// query. The [EventManager] is responsible for multiplexing many listeners
  /// to a single listen in the [SyncEngine] and will perform a listen if it's
  /// the first [QueryListener] added for a query.
  ///
  /// Returns the targetId of the listen call in the [SyncEngine].
  Future<int> addQueryListener(QueryListener queryListener) async {
    final Query query = queryListener.query;

    QueryListenersInfo queryInfo = queries[query];
    final bool firstListen = queryInfo == null;

    if (firstListen) {
      queryInfo = QueryListenersInfo();
      queries[query] = queryInfo;
    }

    queryInfo.listeners.add(queryListener);

    queryListener.onOnlineStateChanged(onlineState);

    if (queryInfo.viewSnapshot != null) {
      await queryListener.onViewSnapshot(queryInfo.viewSnapshot);
    }

    if (firstListen) {
      queryInfo.targetId = await syncEngine.listen(query);
    }
    return queryInfo.targetId;
  }

  /// Removes a previously added listener and returns true if the listener was
  /// found.
  Future<bool> removeQueryListener(QueryListener listener) async {
    final Query query = listener.query;
    final QueryListenersInfo queryInfo = queries[query];
    bool lastListen = false;
    bool found = false;
    if (queryInfo != null) {
      found = queryInfo.listeners.remove(listener);
      lastListen = queryInfo.listeners.isEmpty;
    }

    if (lastListen) {
      queries.remove(query);
      await syncEngine.stopListening(query);
    }

    return found;
  }

  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {
    for (ViewSnapshot viewSnapshot in snapshotList) {
      final Query query = viewSnapshot.query;
      final QueryListenersInfo info = queries[query];
      if (info != null) {
        for (QueryListener listener in info.listeners) {
          await listener.onViewSnapshot(viewSnapshot);
        }
        info.viewSnapshot = viewSnapshot;
      }
    }
  }

  @override
  void onError(Query query, GrpcError error) {
    final QueryListenersInfo info = queries[query];
    if (info != null) {
      for (QueryListener listener in info.listeners) {
        listener.onError(Util.exceptionFromStatus(error));
      }
    }
    queries.remove(query);
  }

  void handleOnlineStateChange(OnlineState onlineState) {
    this.onlineState = onlineState;
    for (QueryListenersInfo info in queries.values) {
      for (QueryListener listener in info.listeners) {
        listener.onOnlineStateChanged(onlineState);
      }
    }
  }
}

class QueryListenersInfo {
  final List<QueryListener> listeners;
  ViewSnapshot viewSnapshot;

  int targetId;

  QueryListenersInfo() : listeners = <QueryListener>[];
}

/// Holds (internal) options for listening
class ListenOptions {
  /// Raise events when only metadata of documents changes
  final bool includeDocumentMetadataChanges;

  /// Raise events when only metadata of the query changes
  final bool includeQueryMetadataChanges;

  /// Wait for a sync with the server when online, but still raise events while
  /// offline.
  final bool waitForSyncWhenOnline;

  const ListenOptions({
    this.includeDocumentMetadataChanges = false,
    this.includeQueryMetadataChanges = false,
    this.waitForSyncWhenOnline = false,
  })  : assert(includeDocumentMetadataChanges != null),
        assert(includeQueryMetadataChanges != null),
        assert(waitForSyncWhenOnline != null);

  const ListenOptions.all()
      : includeDocumentMetadataChanges = true,
        includeQueryMetadataChanges = true,
        waitForSyncWhenOnline = true;

  ListenOptions copyWith({
    bool includeDocumentMetadataChanges,
    bool includeQueryMetadataChanges,
    bool waitForSyncWhenOnline,
  }) {
    return ListenOptions(
      includeDocumentMetadataChanges: includeDocumentMetadataChanges ??
          this.includeDocumentMetadataChanges ??
          false,
      includeQueryMetadataChanges: includeQueryMetadataChanges ??
          this.includeQueryMetadataChanges ??
          false,
      waitForSyncWhenOnline:
          waitForSyncWhenOnline ?? this.waitForSyncWhenOnline ?? false,
    );
  }
}