// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// ClientLibraryGenerator
// **************************************************************************

import 'package:api_builder/_client_utils.dart' as _i2;
import 'package:client_data/account_api.dart' as _i4;
import 'package:client_data/admin_api.dart' as _i7;
import 'package:client_data/package_api.dart' as _i3;
import 'package:client_data/publisher_api.dart' as _i5;
import 'package:client_data/task_api.dart' as _i6;
import 'package:http/http.dart' as _i1;

export 'package:api_builder/_client_utils.dart' show RequestException;

/// Client for invoking `PubApi` through the generated router.
///
/// Reponses other than 2xx causes the methods to throw
/// `RequestException`. JSON encoding/decoding errors are not
/// handled gracefully. End-points that does not return a JSON
/// structure result in a method that returns the response body
/// as bytes
class PubApiClient {
  PubApiClient(String baseUrl, {_i1.Client client})
      : _client = _i2.Client(baseUrl, client: client);

  final _i2.Client _client;

  Future<List<int>> listVersions(String package) async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/packages/$package',
    );
  }

  Future<_i3.VersionInfo> packageVersionInfo(
      String package, String version) async {
    return _i3.VersionInfo.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/$package/versions/$version',
    ));
  }

  Future<List<int>> fetchPackage(String package, String version) async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/packages/$package/versions/$version/archive.tar.gz',
    );
  }

  Future<_i3.UploadInfo> getPackageUploadUrl() async {
    return _i3.UploadInfo.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/versions/new',
    ));
  }

  Future<_i3.SuccessMessage> packageUploadCallback() async {
    return _i3.SuccessMessage.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/versions/newUploadFinish',
    ));
  }

  Future<_i3.SuccessMessage> addUploader(String package) async {
    return _i3.SuccessMessage.fromJson(await _client.requestJson(
      verb: 'post',
      path: '/api/packages/$package/uploaders',
    ));
  }

  Future<_i3.SuccessMessage> removeUploader(
      String package, String email) async {
    return _i3.SuccessMessage.fromJson(await _client.requestJson(
      verb: 'delete',
      path: '/api/packages/$package/uploaders/$email',
    ));
  }

  Future<_i4.InviteStatus> invitePackageUploader(
      String package, _i3.InviteUploaderRequest payload) async {
    return _i4.InviteStatus.fromJson(await _client.requestJson(
      verb: 'post',
      path: '/api/packages/$package/invite-uploader',
      body: payload.toJson(),
    ));
  }

  Future<_i5.PublisherInfo> createPublisher(
      String publisherId, _i5.CreatePublisherRequest payload) async {
    return _i5.PublisherInfo.fromJson(await _client.requestJson(
      verb: 'post',
      path: '/api/publishers/$publisherId',
      body: payload.toJson(),
    ));
  }

  Future<_i5.PublisherInfo> publisherInfo(String publisherId) async {
    return _i5.PublisherInfo.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/publishers/$publisherId',
    ));
  }

  Future<_i5.PublisherInfo> updatePublisher(
      String publisherId, _i5.UpdatePublisherRequest payload) async {
    return _i5.PublisherInfo.fromJson(await _client.requestJson(
      verb: 'put',
      path: '/api/publishers/$publisherId',
      body: payload.toJson(),
    ));
  }

  Future<_i4.InviteStatus> invitePublisherMember(
      String publisherId, _i5.InviteMemberRequest payload) async {
    return _i4.InviteStatus.fromJson(await _client.requestJson(
      verb: 'post',
      path: '/api/publishers/$publisherId/invite-member',
      body: payload.toJson(),
    ));
  }

  Future<_i5.PublisherMembers> listPublisherMembers(String publisherId) async {
    return _i5.PublisherMembers.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/publishers/$publisherId/members',
    ));
  }

  Future<_i5.PublisherMember> publisherMemberInfo(
      String publisherId, String userId) async {
    return _i5.PublisherMember.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/publishers/$publisherId/members/$userId',
    ));
  }

  Future<_i5.PublisherMember> updatePublisherMember(String publisherId,
      String userId, _i5.UpdatePublisherMemberRequest payload) async {
    return _i5.PublisherMember.fromJson(await _client.requestJson(
      verb: 'put',
      path: '/api/publishers/$publisherId/members/$userId',
      body: payload.toJson(),
    ));
  }

  Future<List<int>> removePublisherMember(
      String publisherId, String userId) async {
    return await _client.requestBytes(
      verb: 'delete',
      path: '/api/publishers/$publisherId/members/$userId',
    );
  }

  Future<_i4.Consent> consentInfo(String consentId) async {
    return _i4.Consent.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/account/consent/$consentId',
    ));
  }

  Future<_i4.ConsentResult> resolveConsent(
      String consentId, _i4.ConsentResult payload) async {
    return _i4.ConsentResult.fromJson(await _client.requestJson(
      verb: 'put',
      path: '/api/account/consent/$consentId',
      body: payload.toJson(),
    ));
  }

  Future<List<int>> updateSession(_i4.ClientSessionRequest payload) async {
    return await _client.requestBytes(
      verb: 'post',
      path: '/api/account/session',
      body: payload.toJson(),
    );
  }

  Future<List<int>> invalidateSession() async {
    return await _client.requestBytes(
      verb: 'delete',
      path: '/api/account/session',
    );
  }

  Future<_i4.AccountPkgOptions> accountPackageOptions(String package) async {
    return _i4.AccountPkgOptions.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/account/options/packages/$package',
    ));
  }

  Future<_i4.AccountPublisherOptions> accountPublisherOptions(
      String publisherId) async {
    return _i4.AccountPublisherOptions.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/account/options/publishers/$publisherId',
    ));
  }

  Future<_i4.LikedPackagesRepsonse> listPackageLikes() async {
    return _i4.LikedPackagesRepsonse.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/account/likes',
    ));
  }

  Future<_i4.PackageLikeResponse> getLikePackage(String package) async {
    return _i4.PackageLikeResponse.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/account/likes/$package',
    ));
  }

  Future<_i4.PackageLikeResponse> likePackage(String package) async {
    return _i4.PackageLikeResponse.fromJson(await _client.requestJson(
      verb: 'put',
      path: '/api/account/likes/$package',
    ));
  }

  Future<List<int>> unlikePackage(String package) async {
    return await _client.requestBytes(
      verb: 'delete',
      path: '/api/account/likes/$package',
    );
  }

  Future<List<int>> documentation(String package) async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/documentation/$package',
    );
  }

  Future<List<int>> listPackages() async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/packages',
    );
  }

  Future<List<int>> packageNames() async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/package-names',
    );
  }

  Future<List<int>> packageNameCompletionData() async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/package-name-completion-data',
    );
  }

  Future<List<int>> packageMetrics(String package) async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/packages/$package/metrics',
    );
  }

  Future<_i3.PkgOptions> packageOptions(String package) async {
    return _i3.PkgOptions.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/$package/options',
    ));
  }

  Future<_i3.PkgOptions> setPackageOptions(
      String package, _i3.PkgOptions payload) async {
    return _i3.PkgOptions.fromJson(await _client.requestJson(
      verb: 'put',
      path: '/api/packages/$package/options',
      body: payload.toJson(),
    ));
  }

  Future<_i3.PackagePublisherInfo> getPackagePublisher(String package) async {
    return _i3.PackagePublisherInfo.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/$package/publisher',
    ));
  }

  Future<_i4.PackageLikesCount> getPackageLikes(String package) async {
    return _i4.PackageLikesCount.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/$package/likes',
    ));
  }

  Future<_i3.PackagePublisherInfo> setPackagePublisher(
      String package, _i3.PackagePublisherInfo payload) async {
    return _i3.PackagePublisherInfo.fromJson(await _client.requestJson(
      verb: 'put',
      path: '/api/packages/$package/publisher',
      body: payload.toJson(),
    ));
  }

  Future<_i3.PackagePublisherInfo> removePackagePublisher(
      String package) async {
    return _i3.PackagePublisherInfo.fromJson(await _client.requestJson(
      verb: 'delete',
      path: '/api/packages/$package/publisher',
    ));
  }

  Future<_i3.VersionScore> packageScore(String package) async {
    return _i3.VersionScore.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/$package/score',
    ));
  }

  Future<_i3.VersionScore> packageVersionScore(
      String package, String version) async {
    return _i3.VersionScore.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/packages/$package/versions/$version/score',
    ));
  }

  Future<List<int>> search() async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/api/search',
    );
  }

  Future<List<int>> debug() async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/debug',
    );
  }

  Future<List<int>> packages() async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/packages.json',
    );
  }

  Future<List<int>> packageJson(String package) async {
    return await _client.requestBytes(
      verb: 'get',
      path: '/packages/$package.json',
    );
  }

  Future<_i6.UploadTaskResultResponse> taskUploadResult(
      String package, String version) async {
    return _i6.UploadTaskResultResponse.fromJson(await _client.requestJson(
      verb: 'post',
      path: '/api/tasks/$package/$version/upload',
    ));
  }

  Future<List<int>> taskUploadFinished(String package, String version) async {
    return await _client.requestBytes(
      verb: 'post',
      path: '/api/tasks/$package/$version/finished',
    );
  }

  Future<_i7.AdminListUsersResponse> adminListUsers(
      {String email, String ouid, String ct}) async {
    return _i7.AdminListUsersResponse.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/admin/users',
      query: email != null || ouid != null || ct != null
          ? <String, String>{
              if (email != null) 'email': email,
              if (ouid != null) 'ouid': ouid,
              if (ct != null) 'ct': ct
            }
          : null,
    ));
  }

  Future<List<int>> adminRemoveUser(String userId) async {
    return await _client.requestBytes(
      verb: 'delete',
      path: '/api/admin/users/$userId',
    );
  }

  Future<List<int>> adminRemovePackage(String package) async {
    return await _client.requestBytes(
      verb: 'delete',
      path: '/api/admin/packages/$package',
    );
  }

  Future<List<int>> adminRemovePackageVersion(
      String package, String version) async {
    return await _client.requestBytes(
      verb: 'delete',
      path: '/api/admin/packages/$package/versions/$version',
    );
  }

  Future<_i7.AssignedTags> adminGetAssignedTags(String package) async {
    return _i7.AssignedTags.fromJson(await _client.requestJson(
      verb: 'get',
      path: '/api/admin/packages/$package/assigned-tags',
    ));
  }

  Future<_i7.AssignedTags> adminPostAssignedTags(
      String package, _i7.PatchAssignedTags payload) async {
    return _i7.AssignedTags.fromJson(await _client.requestJson(
      verb: 'post',
      path: '/api/admin/packages/$package/assigned-tags',
      body: payload.toJson(),
    ));
  }
}
