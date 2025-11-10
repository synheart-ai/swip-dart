class BiosignalRecord {
  final String appBiosignalId;
  final String appSessionId;
  final String timestamp;
  final double? respiratoryRate;
  final double? hrvSdnn;
  final double? heartRate;
  final double? accelerometer;
  final double? temperature;
  final double? bloodOxygenSaturation;
  final double? ecg;
  final double? emg;
  final double? eda;
  final List<double>? gyro;
  final double? ppg;
  final double? ibi;

  BiosignalRecord({
    required this.appBiosignalId,
    required this.appSessionId,
    required this.timestamp,
    this.respiratoryRate,
    this.hrvSdnn,
    this.heartRate,
    this.accelerometer,
    this.temperature,
    this.bloodOxygenSaturation,
    this.ecg,
    this.emg,
    this.eda,
    this.gyro,
    this.ppg,
    this.ibi,
  });

  Map<String, dynamic> toJson() {
    return {
      'app_biosignal_id': appBiosignalId,
      'app_session_id': appSessionId,
      'timestamp': timestamp,
      if (respiratoryRate != null) 'respiratory_rate': respiratoryRate,
      if (hrvSdnn != null) 'hrv_sdnn': hrvSdnn,
      if (heartRate != null) 'heart_rate': heartRate!.round(), // API requires integer
      if (accelerometer != null) 'accelerometer': accelerometer,
      if (temperature != null) 'temperature': temperature,
      if (bloodOxygenSaturation != null)
        'blood_oxygen_saturation': bloodOxygenSaturation,
      if (ecg != null) 'ecg': ecg,
      if (emg != null) 'emg': emg,
      if (eda != null) 'eda': eda,
      if (gyro != null) 'gyro': gyro,
      if (ppg != null) 'ppg': ppg,
      if (ibi != null) 'ibi': ibi,
    };
  }
}

