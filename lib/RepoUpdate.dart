/// Class used in repository updates
class RepoUpdate<Id>{

  /// Id of the model
  Id modelId;

  /// Type of the update
  RepoUpdateType type;

  RepoUpdate({
    this.modelId,
    this.type,
  });

}

enum RepoUpdateType {
  get,
  create,
  update,
  delete,
}