class DevicePayload {
  final String deviceId;
  final String platform;
  final String? watchModel;
  final String mobileOsVersion;

  DevicePayload({
    required this.deviceId,
    required this.platform,
    required this.mobileOsVersion,
    this.watchModel,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'platform': platform,
      if (watchModel != null) 'watch_model': watchModel,
      'mobileOS_version': mobileOsVersion,
    };
  }
}
