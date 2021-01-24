// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:collection/collection.dart';

/// Provides a set of fields that can be used to partially patch a document. The [FieldMask] is used in conjunction
/// with [ObjectValue].
///
/// Examples:
///   1. foo - Overwrites foo entirely with the provided value. If foo is not present in the companion [ObjectValue],
///   the field is deleted.
///   2. foo.bar - Overwrites only the field bar of the object foo. If foo is not an object, foo is replaced with an
///   object containing foo.
class FieldMask {
  const FieldMask(this.mask);

  final Set<FieldPath> mask;

  /// Verifies that [fieldPath] is included by at least one field in this field mask.
  ///
  /// This is an O(n) operation, where 'n' is the size of the field mask.
  bool covers(FieldPath fieldPath) {
    for (FieldPath fieldMaskPath in mask) {
      if (fieldMaskPath.isPrefixOf(fieldPath)) {
        return true;
      }
    }

    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldMask && //
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(mask, other.mask);

  @override
  int get hashCode => const DeepCollectionEquality().hash(mask);

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('mask', mask))
        .toString();
  }
}
