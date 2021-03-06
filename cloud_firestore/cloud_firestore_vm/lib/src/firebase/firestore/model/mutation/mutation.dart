// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';

/// Represents a [Mutation] of a document. Different subclasses of Mutation will
/// perform different kinds of changes to a base document. For example, a
/// [SetMutation] replaces the value of a document and a [DeleteMutation]
/// deletes a document.
///
/// In addition to the value of the document mutations also operate on the
/// version. For local mutations (mutations that haven't been committed yet), we
/// preserve the existing version for Set, Patch, and Transform mutations. For
/// local deletes, we reset the version to 0.
///
/// Here's the expected transition table.
///
/// ||||
/// |--- |--- |--- |
/// |MUTATION               |APPLIED TO         |RESULTS IN|
/// |SetMutation            |Document(v3)       |Document(v3)|
/// |SetMutation            |NoDocument(v3)     |Document(v0)|
/// |SetMutation            |null               |Document(v0)|
/// |PatchMutation          |Document(v3)       |Document(v3)|
/// |PatchMutation          |NoDocument(v3)     |NoDocument(v3)|
/// |PatchMutation          |null               |null|
/// |TransformMutation      |Document(v3)       |Document(v3)|
/// |TransformMutation      |NoDocument(v3)     |NoDocument(v3)|
/// |TransformMutation      |null               |null|
/// |DeleteMutation         |Document(v3)       |NoDocument(v0)|
///
/// For acknowledged mutations, we use the [updateTime] of the [WriteResponse] as the resulting
/// version for Set, Patch, and Transform mutations. As deletes have no explicit update time, we use
/// the [commitTime] of the [WriteResponse] for acknowledged deletes.
///
/// If a mutation is acknowledged by the backend but fails the precondition check locally, we return
/// an [UnknownDocument] and rely on Watch to send us the updated version.
///
/// Note that [TransformMutations] don't create [Documents] (in the case of being applied to a
/// [NoDocument]), even though they would on the backend. This is because the client always combines
/// the [TransformMutation] with a [SetMutation] or [PatchMutation] and we only want to apply the
/// transform if the prior mutation resulted in a [Document] (always true for a [SetMutation], but
/// not necessarily for an [PatchMutation]).
abstract class Mutation {
  const Mutation(this.key, this.precondition);

  final DocumentKey key;

  /// The precondition for the mutation.
  final Precondition precondition;

  /// Applies this mutation to the given [MaybeDocument] for the purposes of computing a new remote
  /// document. If the input document doesn't match the expected state (e.g. it is null or
  /// outdated), an [UnknownDocument] can be returned.
  ///
  /// [maybeDoc] is the document to mutate. The input document can be null if the client has no
  /// knowledge of the pre-mutation state of the document.
  ///
  /// [mutationResult] is the result of applying the mutation from the backend.
  ///
  /// Returns the mutated document. The returned document may be an [UnknownDocument], if the
  /// mutation could not be applied to the locally cached base document.
  MaybeDocument applyToRemoteDocument(
      MaybeDocument maybeDoc, MutationResult mutationResult);

  /// Applies this mutation to [maybeDoc] for the purposes of computing the new local view of a
  /// document. Both the input and returned documents can be null.
  ///
  /// [maybeDoc] is the document to mutate. The input document can be null if the client has no
  /// knowledge of the pre-mutation state of the document.
  ///
  /// [baseDoc] is the state of the document prior to this mutation batch. The input document can be
  /// null if the client has no knowledge of the pre-mutation state of the document.
  ///
  /// [localWriteTime] is timestamp indicating the local write time of the batch this mutation is a
  /// part of.
  ///
  /// Returns the mutated document. The returned document may be null, but only if [maybeDoc] was
  /// null and the mutation would not create a new document.
  MaybeDocument applyToLocalView(
      MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime);

  /// If applicable, returns the base value to persist with this mutation. If a
  /// base value is provided, the mutation is always applied to this base value,
  /// even if document has already been updated.
  ///
  /// The base value is a sparse object that consists of only the document
  /// fields for which this mutation contains a non-idempotent transformation
  /// (e.g. a numeric increment). The provided value guarantees consistent
  /// behavior for non-idempotent transforms and allow us to return the same
  /// latency-compensated value even if the backend has already applied the
  /// mutation. The base value is null for idempotent mutations, as they can be
  /// re-played even if the backend has already applied them.
  ///
  /// Returns a base value to store along with the mutation, or null for
  /// idempotent mutations.
  ObjectValue extractBaseValue(MaybeDocument maybeDoc);

  /// Helper for derived classes to implement .equals.
  bool hasSameKeyAndPrecondition(Mutation other) {
    return key == other.key && precondition == other.precondition;
  }

  /// Helper for derived classes to implement .hashCode.
  int keyAndPreconditionHashCode() {
    return key.hashCode * 31 + precondition.hashCode;
  }

  void verifyKeyMatches(MaybeDocument maybeDoc) {
    if (maybeDoc != null) {
      hardAssert(maybeDoc.key == key,
          'Can only apply a mutation to a document with the same key');
    }
  }

  /// Returns the version from the given document for use as the result of a mutation. Mutations are
  /// defined to return the version of the base document only if it is an existing document. Deleted
  /// and unknown documents have a post-mutation version of [SnapshotVersion.none].
  static SnapshotVersion getPostMutationVersion(MaybeDocument maybeDoc) {
    if (maybeDoc is Document) {
      return maybeDoc.version;
    } else {
      return SnapshotVersion.none;
    }
  }
}
