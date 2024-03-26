import 'package:flutter/cupertino.dart';
import 'package:object_detection_app/models/screen_params.dart';
class Recognition {
  final int _id;
  final String _label;
  final double _score;
  final Rect _location;
  String? approximatePosition;
  double distanceToDetectedObject;
  double? approximateDistance2;

  double? approximateDistance; // New property for distance

  Recognition(this._id, this._label, this._score, this._location, {this.distanceToDetectedObject = 0.0, this.approximatePosition, this.approximateDistance2,this.approximateDistance});

  int get id => _id;
  String get label => _label;
  double get score => _score;
  Rect get location => _location;

  Offset get centerPoint {
    final left = _location.left;
    final right = _location.right;
    final top = _location.top;
    final bottom = _location.bottom;

    final centerX = (left + right) / 2;
    final centerY = (top + bottom) / 2;

    return Offset(centerX, centerY);
  }

  Rect get renderLocation {
    final double scaleX = ScreenParams.screenPreviewSize.width / 300;
    final double scaleY = ScreenParams.screenPreviewSize.height / 300;
    return Rect.fromLTWH(
      _location.left * scaleX,
      _location.top * scaleY,
      _location.width * scaleX,
      _location.height * scaleY,
    );
  }

  @override
  String toString() {
    print(id);
    print(label);
    print(score);
    print(location);
    print('Center point: $centerPoint');
    return 'Recognition(id: $id, label: $label, score: $score, location: $location, distanceToDetectedObject: $distanceToDetectedObject)';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': _id,
      'label': _label,
      'score': _score,
      'location': {'left': _location.left, 'top': _location.top, 'width': _location.width, 'height': _location.height},
      'approximatePosition': approximatePosition,
      'distanceToDetectedObject': distanceToDetectedObject,
    };
  }

  factory Recognition.fromJson(Map<String, dynamic> json) {
    return Recognition(
      json['id'] as int,
      json['label'] as String,
      json['score'] as double,
      Rect.fromLTWH(
        json['location']['left'] as double,
        json['location']['top'] as double,
        json['location']['width'] as double,
        json['location']['height'] as double,
      ),
      distanceToDetectedObject: json['distanceToDetectedObject'] as double,
      approximatePosition: json['approximatePosition'] as String?,
      approximateDistance2: json['approximateDistance2'] as double,
      approximateDistance: json['approximateDistance'] as double,
    );
  }
}