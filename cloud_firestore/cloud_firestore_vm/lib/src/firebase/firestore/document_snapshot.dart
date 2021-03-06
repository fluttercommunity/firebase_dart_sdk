// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/snapshot_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:meta/meta.dart';

/// A [DocumentSnapshot] contains data read from a document in your [Firestore] database. The data can be extracted with
/// the [data] or [get] methods.
///
/// If the [DocumentSnapshot‘ points to a non-existing document, [data] and its corresponding methods will return null.
/// You can always explicitly check for a document's existence by calling [exists].
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class DocumentSnapshot {
  DocumentSnapshot(
    this._firestore,
    this._key,
    this.document, {
    @required bool isFromCache,
    @required bool hasPendingWrites,
  })  : metadata = SnapshotMetadata(hasPendingWrites, isFromCache),
        assert(_firestore != null),
        assert(_key != null);

  factory DocumentSnapshot.fromDocument(
    Firestore firestore,
    Document doc, {
    @required bool isFromCache,
    @required bool hasPendingWrites,
  }) {
    return DocumentSnapshot(firestore, doc.key, doc,
        isFromCache: isFromCache, hasPendingWrites: hasPendingWrites);
  }

  factory DocumentSnapshot.fromNoDocument(
    Firestore firestore,
    DocumentKey key, {
    @required bool isFromCache,
    @required bool hasPendingWrites,
  }) {
    return DocumentSnapshot(firestore, key, null,
        isFromCache: isFromCache, hasPendingWrites: hasPendingWrites);
  }

  final Firestore _firestore;

  final DocumentKey _key;

  /// Is null if the document doesn't exist
  final Document document;

  /// The metadata for this document snapshot.
  final SnapshotMetadata metadata;

  /// The id of the document.
  String get id => _key.path.last;

  /// Returns true if the document existed in this snapshot.
  bool get exists => document != null;

  /// Returns the fields of the document as a Map or null if the document doesn't exist. Field values will be converted
  /// to their native Dart representation.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  Map<String, Object> get data => getData(ServerTimestampBehavior.none);

  /// Returns the fields of the document as a Map or null if the document doesn't exist. Field values will be converted
  /// to their native Dart representation.
  ///
  /// [serverTimestampBehavior] Configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  Map<String, Object> getData(ServerTimestampBehavior serverTimestampBehavior) {
    checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');
    if (document == null) {
      return null;
    } else {
      final _FieldValueOptions fieldValueOptions =
          _FieldValueOptions(serverTimestampBehavior: serverTimestampBehavior);
      return _convertObject(document.data, fieldValueOptions);
    }
  }

  /// Returns whether or not the field exists in the document. Returns false if the document does not exist.
  ///
  /// [field] the path to the field.
  ///
  /// Returns true if the field exists.
  bool contains(String field) {
    return containsPath(FieldPath.fromDotSeparatedPath(field));
  }

  /// Returns whether or not the field exists in the document. Returns false if the document does  not exist.
  ///
  /// [fieldPath] the path to the field.
  ///
  /// Returns true if the field exists.
  bool containsPath(FieldPath fieldPath) {
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    return (document != null) &&
        (document.getField(fieldPath.internalPath) != null);
  }

  Object operator [](String field) => get(field);

  /// Returns the value at the field or null if the field doesn't exist.
  ///
  /// [field] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the value at the given field or null.
  Object get(String field, [ServerTimestampBehavior serverTimestampBehavior]) {
    return getField(FieldPath.fromDotSeparatedPath(field),
        serverTimestampBehavior ?? ServerTimestampBehavior.none);
  }

  /// Returns the value at the field or null if the field or document doesn't exist.
  ///
  /// [fieldPath] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the value at the given field or null.
  Object getField(FieldPath fieldPath,
      [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');

    final _FieldValueOptions fieldValueOptions =
        _FieldValueOptions(serverTimestampBehavior: serverTimestampBehavior);
    return _getInternal(fieldPath.internalPath, fieldValueOptions);
  }

  /// Returns the value of the field as a bool. If the value is not a bool this will throw a state error.
  ///
  /// [field] the path to the field.
  ///
  /// Returns the value of the field
  bool getBool(String field) => _getTypedValue<bool>(field);

  /// Returns the value of the field as a double.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a number.
  /// Returns the value of the field
  double getDouble(String field) {
    final num val = _getTypedValue(field);
    return val != null ? val.toDouble() : null;
  }

  /// Returns the value of the field as a int.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a number.
  /// Returns the value of the field
  int getInt(String field) {
    final num val = _getTypedValue(field);
    return val != null ? val.toInt() : null;
  }

  /// Returns the value of the field as a String.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a String.
  /// Returns the value of the field
  String getString(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DateTime].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Throws [StateError] if the value is not a Date.
  /// Returns the value of the field
  DateTime getDate(String field,
      [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    checkNotNull(field, 'Provided field path must not be null.');
    checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');
    final Object maybeDate = _getInternal(
      FieldPath.fromDotSeparatedPath(field).internalPath,
      _FieldValueOptions(
        serverTimestampBehavior: serverTimestampBehavior,
        timestampsInSnapshotsEnabled: false,
      ),
    );
    return _castTypedValue(maybeDate, field);
  }

  /// Returns the value of the field as a [Timestamp].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Throws [StateError] if the value is not a timestamp field.
  /// Returns the value of the field
  Timestamp getTimestamp(String field,
      [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    checkNotNull(field, 'Provided field path must not be null.');
    checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');
    final Object maybeTimestamp = _getInternal(
      FieldPath.fromDotSeparatedPath(field).internalPath,
      _FieldValueOptions(serverTimestampBehavior: serverTimestampBehavior),
    );
    return _castTypedValue(maybeTimestamp, field);
  }

  /// Returns the value of the field as a [Blob].
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a Blob.
  /// Returns the value of the field
  Blob getBlob(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [GeoPoint].
  ///
  /// [field] The path to the field.
  ///
  /// Throws [StateError] if the value is not a [GeoPoint].
  /// Returns the value of the field
  GeoPoint getGeoPoint(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DocumentReference].
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a [DocumentReference].
  /// Returns the value of the field
  DocumentReference getDocumentReference(String field) => _getTypedValue(field);

  /// Gets the reference to the document.
  ///
  /// Returns the reference to the document.
  DocumentReference get reference => DocumentReference(_key, _firestore);

  T _getTypedValue<T>(String field) {
    checkNotNull(field, 'Provided field must not be null.');
    final Object value = get(field, ServerTimestampBehavior.none);
    return _castTypedValue<T>(value, field);
  }

  T _castTypedValue<T>(Object value, String field) {
    if (value == null) {
      return null;
    }

    try {
      final T result = value;
      return result;
    } on CastError catch (_) {
      throw StateError(
          'Field \'$field\' is not a $T, but it is ${value.runtimeType}');
    }
  }

  Object _convertValue(FieldValue value, _FieldValueOptions options) {
    if (value is ObjectValue) {
      return _convertObject(value, options);
    } else if (value is ArrayValue) {
      return _convertArray(value, options);
    } else if (value is ReferenceValue) {
      return _convertReference(value);
    } else if (value is TimestampValue) {
      return _convertTimestamp(value, options);
    } else if (value is ServerTimestampValue) {
      return _convertServerTimestamp(value, options);
    } else {
      return value.value;
    }
  }

  Object _convertServerTimestamp(
      ServerTimestampValue value, _FieldValueOptions options) {
    switch (options.serverTimestampBehavior) {
      case ServerTimestampBehavior.previous:
        return value.previousValue;
      case ServerTimestampBehavior.estimate:
        return value.localWriteTime;
      default:
        return value.value;
    }
  }

  Object _convertTimestamp(TimestampValue value, _FieldValueOptions options) {
    final Timestamp timestamp = value.value;
    if (options.timestampsInSnapshotsEnabled) {
      return timestamp;
    } else {
      return timestamp.toDate();
    }
  }

  Object _convertReference(ReferenceValue value) {
    final DocumentKey key = value.value;
    final DatabaseId refDatabase = value.databaseId;
    final DatabaseId database = _firestore.databaseId;
    if (refDatabase != database) {
      // TODO(long1eu): Somehow support foreign references.
      Log.w('$DocumentSnapshot',
          'Document ${key.path} contains a document reference within a different database (${refDatabase.projectId}/${refDatabase.databaseId}) which is not supported. It will be treated as a reference in the current database (${database.projectId}/${database.databaseId}) instead.');
    }
    return DocumentReference(key, _firestore);
  }

  Map<String, Object> _convertObject(
      ObjectValue objectValue, _FieldValueOptions options) {
    final Map<String, Object> result = <String, Object>{};
    for (MapEntry<String, FieldValue> entry in objectValue.internalValue) {
      result[entry.key] = _convertValue(entry.value, options);
    }
    return result;
  }

  List<Object> _convertArray(
      ArrayValue arrayValue, _FieldValueOptions options) {
    final List<Object> result = List<Object>(arrayValue.internalValue.length);
    int i = 0;
    for (FieldValue v in arrayValue.internalValue) {
      result[i] = _convertValue(v, options);
      i++;
    }
    return result;
  }

  Object _getInternal(model.FieldPath fieldPath, _FieldValueOptions options) {
    if (document != null) {
      final FieldValue val = document.getField(fieldPath);
      if (val != null) {
        return _convertValue(val, options);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSnapshot &&
          runtimeType == other.runtimeType &&
          _firestore == other._firestore &&
          _key == other._key &&
          (document == null
              ? other.document == null
              : document == other.document) &&
          metadata == other.metadata;

  @override
  int get hashCode {
    return _firestore.hashCode * 31 +
        _key.hashCode * 31 +
        (document == null ? 0 : document.hashCode) * 31 +
        metadata.hashCode * 31;
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('key', _key)
          ..add('metadata', metadata)
          ..add('document', document))
        .toString();
  }
}

/// Holds settings that define field value deserialization options.
class _FieldValueOptions {
  _FieldValueOptions({
    this.serverTimestampBehavior,
    this.timestampsInSnapshotsEnabled = true,
  });

  final ServerTimestampBehavior serverTimestampBehavior;
  final bool timestampsInSnapshotsEnabled;
}
