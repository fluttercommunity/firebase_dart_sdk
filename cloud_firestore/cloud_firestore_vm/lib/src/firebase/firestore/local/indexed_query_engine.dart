// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/index_range.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/index_cursor.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

const double _kHighSelectivity = 1.0;
const double _kLowSelectivity = 0.5;

/// [ArrayValue] and [ObjectValue] are currently considered low cardinality
/// because we don't index them uniquely.
const List<Type> _kLowCardinalityTypes = <Type>[
  BoolValue,
  ArrayValue,
  ObjectValue
];

/// An indexed implementation of [QueryEngine] which performs fairly efficient
/// queries.
///
/// [IndexedQueryEngine] performs only one index lookup and picks an index to
/// use based on an estimate of a query's [filter] or [orderBy] selectivity.
///
/// For queries with filters, [IndexedQueryEngine] distinguishes between two
/// categories of query filters: High selectivity filters are expected to return
/// a lower number of results from the index, while low selectivity filters only
/// marginally prune the search space.
///
/// We determine the best filter to use based on the combination of two static
/// rules, which take into account both the operator and field values type.
///
/// For operators, this assignment is as follows:
///   * HIGH_SELECTIVITY: '='
///   * LOW_SELECTIVITY: '<', <=', '>=', '>'
///
/// For field value types, this assignment is:
///   * HIGH_SELECTIVITY: [BlobValue], [DoubleValue], [GeoPointValue],
///   [NumberValue], [ReferenceValue], [StringValue], [TimestampValue],
///   [NullValue]
///   * LOW_SELECTIVITY: [ArrayValue], [ObjectValue], [BoolValue]
///
/// Note that we consider [NullValue] a high selectivity filter as we only
/// support equals comparisons against 'null' and expect most data to be
/// non-null.
///
/// In the absence of filters, [IndexedQueryEngine] performs an index lookup
/// based on the first explicitly specified field in the [orderBy] clause.
/// Fields in an [orderBy] only match documents that contains these fields and
/// can hence optimize our lookups by providing some selectivity.
///
/// A full collection scan is therefore only needed when no [filters] or
/// [orderBy] constraints are specified.
class IndexedQueryEngine implements QueryEngine {
  const IndexedQueryEngine(this.localDocuments, this.collectionIndex);

  final LocalDocumentsView localDocuments;
  final SQLiteCollectionIndex collectionIndex;

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
    Query query,
  ) {
    return query.isDocumentQuery
        ? localDocuments.getDocumentsMatchingQuery(query)
        : _performCollectionQuery(query);
  }

  @override
  void handleDocumentChange(
      MaybeDocument oldDocument, MaybeDocument newDocument) {
    // TODO(long1eu): Determine changed fields and make appropriate
    //  addEntry() / removeEntry() on SQLiteCollectionIndex.
    throw StateError('Not yet implemented.');
  }

  /// Executes the query using both indexes and post-filtering.
  Future<ImmutableSortedMap<DocumentKey, Document>> _performCollectionQuery(
    Query query,
  ) async {
    hardAssert(!query.isDocumentQuery,
        'matchesCollectionQuery called with document query.');

    final IndexRange indexRange = _extractBestIndexRange(query);
    ImmutableSortedMap<DocumentKey, Document> filteredResults;

    if (indexRange != null) {
      filteredResults = await _performQueryUsingIndex(query, indexRange);
    } else {
      hardAssert(query.filters.isEmpty,
          'If there are any filters, we should be able to use an index.');
      // TODO(long1eu): Call overlay.getCollectionDocuments(query.path) and
      //  filter the results (there may still be startAt/endAt bounds that
      //  apply).
      filteredResults = await localDocuments.getDocumentsMatchingQuery(query);
    }

    return filteredResults;
  }

  /// Applies 'filter' to the index cursor, looks up the relevant documents from
  /// the local documents view and returns
  /// all matches.
  Future<ImmutableSortedMap<DocumentKey, Document>> _performQueryUsingIndex(
      Query query, IndexRange indexRange) async {
    ImmutableSortedMap<DocumentKey, Document> results =
        DocumentCollections.emptyDocumentMap();
    final IndexCursor cursor =
        collectionIndex.getCursor(query.path, indexRange);
    try {
      while (cursor.next) {
        final Document document =
            await localDocuments.getDocument(cursor.documentKey);
        if (query.matches(document)) {
          results = results.insert(cursor.documentKey, document);
        }
      }
    } finally {
      cursor.close();
    }

    return results;
  }

  /// Determines a single filter's selectivity by multiplying the implied
  /// selectivity of the filter operator and the type of its operand.
  ///
  /// Returns a number from 0.0 to 1.0 (inclusive), where higher numbers
  /// indicate higher selectivity
  static double _estimateFilterSelectivity(Filter filter) {
    hardAssert(filter is FieldFilter, 'Filter type expected to be FieldFilter');

    final FieldFilter fieldFilter = filter;
    if (fieldFilter.value == null || fieldFilter.value == DoubleValue.nan) {
      return _kHighSelectivity;
    } else {
      final double operatorSelectivity =
          fieldFilter.operator == FilterOperator.equal
              ? _kHighSelectivity
              : _kLowSelectivity;
      final double typeSelectivity =
          _kLowCardinalityTypes.contains(fieldFilter.value.runtimeType)
              ? _kLowSelectivity
              : _kHighSelectivity;

      return typeSelectivity * operatorSelectivity;
    }
  }

  /// Returns an optimized [IndexRange] for this query.
  ///
  /// The [IndexRange] is computed based on the estimated selectivity of the
  /// query [filters] and [orderBy] constraints. If no [filters] or [orderBy]
  /// constraints are specified, it returns null.
  static IndexRange _extractBestIndexRange(Query query) {
    // TODO(long1eu): consider any startAt/endAt bounds on the query.
    double currentSelectivity = -1.0;

    if (query.filters.isNotEmpty) {
      Filter selectedFilter;
      for (Filter currentFilter in query.filters) {
        final double estimatedSelectivity =
            _estimateFilterSelectivity(currentFilter);
        if (estimatedSelectivity > currentSelectivity) {
          selectedFilter = currentFilter;
          currentSelectivity = estimatedSelectivity;
        }
      }
      hardAssert(selectedFilter != null, 'Filter should be defined');
      return _convertFilterToIndexRange(selectedFilter);
    } else {
      // If there are no filters, use the first orderBy constraint when
      // performing the index lookup. This index lookup will remove results that
      // do not contain the field we use for ordering.
      final FieldPath orderPath = query.orderByConstraints[0].field;
      if (orderPath != FieldPath.keyPath) {
        return IndexRange(fieldPath: query.orderByConstraints[0].field);
      }
    }

    return null;
  }

  /// Creates an [IndexRange] that is guaranteed to capture all values that
  /// match the given filter. The determined [IndexRange] is likely
  /// overselective and requires post-filtering.
  static IndexRange _convertFilterToIndexRange(Filter filter) {
    if (filter is FieldFilter) {
      final FieldFilter relationFilter = filter;
      final FieldValue filterValue = relationFilter.value;
      switch (relationFilter.operator) {
        case FilterOperator.equal:
          return IndexRange(
            fieldPath: filter.field,
            start: filterValue,
            end: filterValue,
          );
        case FilterOperator.lessThanOrEqual:
        case FilterOperator.lessThan:
          return IndexRange(
            fieldPath: filter.field,
            end: filterValue,
          );
        case FilterOperator.graterThan:
        case FilterOperator.graterThanOrEqual:
          return IndexRange(
            fieldPath: filter.field,
            start: filterValue,
          );
        default:
          // TODO(long1eu): Add support for ARRAY_CONTAINS.
          throw fail('Unexpected operator in query filter');
      }
    }
    return IndexRange(fieldPath: filter.field);
  }
}
