library paulonia_repository;

import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:paulonia_document_service/paulonia_document_service.dart';
import 'package:paulonia_repository/PauloniaModel.dart';
import 'package:paulonia_repository/RepoUpdate.dart';
import 'package:paulonia_repository/constants.dart';

/// Abstract class for create a Repository
abstract class PauloniaRepository<Id, Model extends PauloniaModel<Id>>
    extends GetxService {
  /// Getter of the collection reference of this repository.
  ///
  /// Is needed override this
  CollectionReference? get collectionReference => _collectionReference;

  /// Repository map that stores the models of the repository
  ///
  /// All models that have been brought are stored in this map.
  /// Also this repository is used to get the models without call the database
  /// and keep them in sync across all the app
  final HashMap<Id, Model> repositoryMap = HashMap();

  /// Gets a model from a document snapshot
  Model getFromDocSnap(DocumentSnapshot docSnap);

  /// Gets a model list from a document snapshot list
  Future<List<Model>> getFromDocSnapList(
      List<DocumentSnapshot> docSnapList) async {
    List<Model> res = [];
    for (DocumentSnapshot docSnap in docSnapList) {
      res.add(getFromDocSnap(docSnap));
    }
    return res;
  }

  /// Adds a listener to this repository
  ///
  /// [listener] is called when there is a change in some model in [repositoryMap]
  /// and you set the property to notify in the function.
  /// This serves to keep the controllers that make use of the models in this repository notified
  /// and has the same data. (Only if this repositoru is used in multiple controllers)
  void addListener(Function(List<RepoUpdate<Id>>) listener) {
    _repositoryStream.stream.listen(listener);
  }

  /// Gets a model from [id]
  ///
  /// This function returns the model if is in [repositoryMap].
  /// If not, then it gets the model from the database and stores it into [repositoryMap]
  ///
  /// * Set [cache] to true to get the model from the cache of the database.
  /// * Set [refreshRepoData] to always get the data from the database and
  /// rewrite it into [repositoryMap]
  /// * Set [notify] to call [_update()] function and notify to all listener
  /// that is a change in the model with [id] in [repositoryMap]. This is only when
  /// the model is obtained from the database and estored in [repositoryMap].
  Future<Model?> getFromId(
    Id id, {
    bool cache = false,
    bool refreshRepoData = false,
    bool notify = false,
  }) async {
    if (!refreshRepoData) {
      Model? res = repositoryMap[id];
      if (res != null) return res;
    }
    Query query =
        collectionReference!.where(FieldPath.documentId, isEqualTo: id);
    QuerySnapshot? queryRes = await PauloniaDocumentService.runQuery(query, cache);
    if (queryRes == null || queryRes.docs.isEmpty) return null;
    Model res = (await getFromDocSnapList(queryRes.docs)).first;
    repositoryMap[id] = res;
    if (notify) update(RepoUpdateType.get, ids: [id]);
    return res;
  }

  /// Gets a model list from an id list
  ///
  /// This function verifies what models are in [repositoryMap]. Those that are not
  /// in [repositoryMap] are obtained from the database.
  /// The function splits the list in mini list of [FirestoreConstants.ARRAY_QUERIES_ITEM_LIMIT]
  /// of size and use [_getFromIdList()] for get the models
  ///
  /// * Set [cache] to true to get the model from the cache of the database
  /// * Set [refreshRepoData] to always get the data from the database and
  /// rewrite it into [repositoryMap]
  /// * Set [notify] to call [_update()] function and notify to all listener
  /// that is a change in [repositoryMap] in all models that are obtained from the database.
  Future<List<Model>> getFromIdList(
    List<Id> idList, {
    bool cache = false,
    bool refreshRepoData = false,
    bool notify = false,
  }) async {
    List<Id> _idList = [];
    List<Model> res = [];
    if (!refreshRepoData) {
      Model? modelRes;
      for (Id id in idList) {
        modelRes = repositoryMap[id];
        if (modelRes != null)
          res.add(modelRes);
        else
          _idList.add(id);
      }
    } else
      _idList = idList;
    List<Model> newModels = [];
    if (_idList.length <= PauloniaRepoConstants.ARRAY_QUERIES_ITEM_LIMIT) {
      newModels.addAll(await (_getFromIdList(_idList, cache: cache)
          as FutureOr<Iterable<Model>>));
      addInRepository(newModels);
      if (_idList.isNotEmpty && notify)
        update(RepoUpdateType.get, ids: _idList);
      res.addAll(newModels);
      return res;
    }
    int start = 0;
    int end = PauloniaRepoConstants.ARRAY_QUERIES_ITEM_LIMIT;
    while (true) {
      if (end > _idList.length) end = _idList.length;
      if (end == start) break;
      newModels.addAll(await (_getFromIdList(
          _idList.getRange(start, end).toList(),
          cache: cache) as FutureOr<Iterable<Model>>));
      start = end;
      end += PauloniaRepoConstants.ARRAY_QUERIES_ITEM_LIMIT;
    }
    addInRepository(newModels);
    if (_idList.isNotEmpty && notify) update(RepoUpdateType.get, ids: _idList);
    res.addAll(newModels);
    return res;
  }

  /// This function adds [models] into [repositoryMap]
  ///
  /// ! Not use this function outside the repositories
  ///
  /// In the extended class, this function has to be called always for the models
  /// obtained from the database
  void addInRepository(List<Model> models) {
    for (Model model in models) {
      repositoryMap[model.id] = model;
    }
  }

  /// This function delete the models with [ids] from [repositoryMap]
  ///
  /// ! Not use this function outside the repositories
  ///
  /// In the extended class, this function has to be called always for the models
  /// deleted from the database
  void deleteInRepository(List<Id> ids) {
    for (Id id in ids) {
      repositoryMap.remove(id);
    }
  }

  /// This functions notify in [_repositoryStream] that are a change in the models
  /// in [repositoryMap]
  ///
  /// You can use [ids] to update a list of ids or you can use [models] to update
  /// a list of models. The type of all updates will be [updateType]
  ///
  /// ! Not use this function outside the repositories
  ///
  /// In the extended class, this function has to be called always for the models
  /// obtained from the database. (like getFromId)
  void update(RepoUpdateType updateType, {List<Id>? ids, List<Model>? models}) {
    if (ids == null && models == null) return;
    List<RepoUpdate> updates;
    if (ids != null) {
      updates =
          ids.map((e) => RepoUpdate<Id>(modelId: e, type: updateType)).toList();
    } else {
      updates = models!
          .map((e) => RepoUpdate<Id>(modelId: e.id, type: updateType))
          .toList();
    }
    _repositoryStream.add(updates as List<RepoUpdate<Id>>);
  }

  /// This functions notify in [_repositoryStream] that are a change in the models
  /// in [repositoryMap]
  ///
  /// You can use [ids] to update a list of ids or you can use [models] to update
  /// a list of models.
  /// Is needed the [updateTypes] list in the order of the ids or models to
  /// set the update type in each model.
  ///
  /// ! Not use this function outside the repositories
  ///
  /// In the extended class, this function has to be called always for the models
  /// obtained from the database. (like getFromId)
  void updateDifferentTypes(List<RepoUpdateType> updateTypes,
      {List<Id>? ids, List<Model>? models}) {
    if (ids == null && models == null) return;
    List<RepoUpdate> updates = [];
    for (int i = 0; i < updateTypes.length; i++) {
      if (ids != null) {
        updates.add(RepoUpdate<Id>(
          modelId: ids[i],
          type: updateTypes[i],
        ));
      } else {
        updates.add(RepoUpdate<Id>(
          modelId: models![i].id,
          type: updateTypes[i],
        ));
      }
    }
    _repositoryStream.add(updates as List<RepoUpdate<Id>>);
  }

  /// Gets a model list from an id list
  ///
  /// This function is used in [getFromIdList()]
  /// It makes the query and gets the models with the ids id [idList]
  ///
  /// * Set [cache] to true to get the models from the cache of the database
  Future<List<Model>?> _getFromIdList(
    List<Id> idList, {
    bool cache = false,
  }) async {
    if (idList.length > PauloniaRepoConstants.ARRAY_QUERIES_ITEM_LIMIT) {
      return null;
    }
    if (idList.isEmpty) return [];
    Query query = collectionReference!
        .where(FieldPath.documentId, whereIn: idList)
        .limit(PauloniaRepoConstants.ARRAY_QUERIES_ITEM_LIMIT);
    QuerySnapshot? queryRes = await PauloniaDocumentService.runQuery(query, cache);
    if (queryRes == null) return [];
    return getFromDocSnapList(queryRes.docs);
  }

  /// Private value of the collection reference of this repository
  CollectionReference? _collectionReference;

  /// Stream controller that handles the changes in [repositoryMap]
  final StreamController<List<RepoUpdate<Id>>> _repositoryStream =
      StreamController<List<RepoUpdate<Id>>>.broadcast();
}
