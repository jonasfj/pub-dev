// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_api.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UploadTaskResultResponse _$UploadTaskResultResponseFromJson(
    Map<String, dynamic> json) {
  return UploadTaskResultResponse(
    dartdocBlobId: json['dartdocBlobId'] as String,
    panaLogId: json['panaLogId'] as String,
    dartdocBlob: json['dartdocBlob'] == null
        ? null
        : UploadInfo.fromJson(json['dartdocBlob'] as Map<String, dynamic>),
    dartdocIndex: json['dartdocIndex'] == null
        ? null
        : UploadInfo.fromJson(json['dartdocIndex'] as Map<String, dynamic>),
    panaLog: json['panaLog'] == null
        ? null
        : UploadInfo.fromJson(json['panaLog'] as Map<String, dynamic>),
    panaReport: json['panaReport'] == null
        ? null
        : UploadInfo.fromJson(json['panaReport'] as Map<String, dynamic>),
  );
}

Map<String, dynamic> _$UploadTaskResultResponseToJson(
        UploadTaskResultResponse instance) =>
    <String, dynamic>{
      'dartdocBlobId': instance.dartdocBlobId,
      'panaLogId': instance.panaLogId,
      'dartdocBlob': instance.dartdocBlob,
      'dartdocIndex': instance.dartdocIndex,
      'panaLog': instance.panaLog,
      'panaReport': instance.panaReport,
    };
