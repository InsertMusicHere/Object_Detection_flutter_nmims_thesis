
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:object_detection_app/models/recognition.dart';
import 'package:object_detection_app/utils/image_utils.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' as math;


enum _Codes {
  init,
  busy,
  ready,
  detect,
  result,
}

/// A command sent between [Detector] and [_DetectorServer].
class _Command {
  const _Command(this.code, {this.args});

  final _Codes code;
  final List<Object>? args;
}

/// A Simple Detector that handles object detection via Service
///
/// All the heavy operations like pre-processing, detection, ets,
/// are executed in a background isolate.
/// This class just sends and receives messages to the isolate.
class Detector {
  // static const String _modelPath = 'assets/models/yolov2_tiny2.tflite';
  // static const String _labelPath = 'assets/models/yolov2_tiny2.txt';

  static const String _modelPath = 'assets/models/ssd_mobilenet.tflite';
  static const String _labelPath = 'assets/models/labelmap.txt';

  Detector._(this._isolate, this._interpreter, this._labels);

  final Isolate _isolate;
  late final Interpreter _interpreter;
  late final List<String> _labels;

  // To be used by detector (from UI) to send message to our Service ReceivePort
  late final SendPort _sendPort;

  bool _isReady = false;

  // // Similarly, StreamControllers are stored in a queue so they can be handled
  // // asynchronously and serially.
  final StreamController<Map<String, dynamic>> resultsStream =
  StreamController<Map<String, dynamic>>();

  /// Open the database at [path] and launch the server on a background isolate..
  static Future<Detector> start() async {
    final ReceivePort receivePort = ReceivePort();
    // sendPort - To be used by service Isolate to send message to our ReceiverPort
    final Isolate isolate =
    await Isolate.spawn(_DetectorServer._run, receivePort.sendPort);

    final Detector result = Detector._(
      isolate,
      await _loadModel(),
      await _loadLabels(),
    );
    receivePort.listen((message) {
      result._handleCommand(message as _Command);
    });
    return result;
  }

  static Future<Interpreter> _loadModel() async {
    final interpreterOptions = InterpreterOptions();

    // Use XNNPACK Delegate
    if (Platform.isAndroid) {
      interpreterOptions.addDelegate(XNNPackDelegate());
    }

    return Interpreter.fromAsset(
      _modelPath,
      options: interpreterOptions..threads = 4,
    );
  }

  static Future<List<String>> _loadLabels() async {
    return (await rootBundle.loadString(_labelPath)).split('\n');
  }

  /// Starts CameraImage processing
  void processFrame(CameraImage cameraImage) {
    if (_isReady) {
      _sendPort.send(_Command(_Codes.detect, args: [cameraImage]));
    }
  }

  /// Handler invoked when a message is received from the port communicating
  /// with the database server.
  void _handleCommand(_Command command) {
    switch (command.code) {
      case _Codes.init:
        _sendPort = command.args?[0] as SendPort;
        // ----------------------------------------------------------------------
        // Before using platform channels and plugins from background isolates we
        // need to register it with its root isolate. This is achieved by
        // acquiring a [RootIsolateToken] which the background isolate uses to
        // invoke [BackgroundIsolateBinaryMessenger.ensureInitialized].
        // ----------------------------------------------------------------------
        RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;
        _sendPort.send(_Command(_Codes.init, args: [
          rootIsolateToken,
          _interpreter.address,
          _labels,
        ]));
        break;
      case _Codes.ready:
        _isReady = true;
        break;
      case _Codes.busy:
        _isReady = false;
        break;
      case _Codes.result:
        _isReady = true;
        resultsStream.add(command.args?[0] as Map<String, dynamic>);
        break;
      default:
        debugPrint('Detector unrecognized command: ${command.code}');
    }
  }

  /// Kills the background isolate and its detector server.
  void stop() {
    _isolate.kill();
  }
}

/// The portion of the [Detector] that runs on the background isolate.
///
/// This is where we use the new feature Background Isolate Channels, which
/// allows us to use plugins from background isolates.
class _DetectorServer {
  /// Input size of image (height = width = 300)
  static const int mlModelInputSize = 300;

  /// Result confidence threshold
  static const double confidence = 0.48;
  static const double confidence2 = 0.30;
  Interpreter? _interpreter;
  List<String>? _labels;

  _DetectorServer(this._sendPort);

  final SendPort _sendPort;

  // ----------------------------------------------------------------------
  // Here the plugin is used from the background isolate.
  // ----------------------------------------------------------------------

  /// The main entrypoint for the background isolate sent to [Isolate.spawn].
  static void _run(SendPort sendPort) {
    ReceivePort receivePort = ReceivePort();
    final _DetectorServer server = _DetectorServer(sendPort);
    receivePort.listen((message) async {
      final _Command command = message as _Command;
      await server._handleCommand(command);
    });
    // receivePort.sendPort - used by UI isolate to send commands to the service receiverPort
    sendPort.send(_Command(_Codes.init, args: [receivePort.sendPort]));
  }

  /// Handle the [command] received from the [ReceivePort].
  Future<void> _handleCommand(_Command command) async {
    switch (command.code) {
      case _Codes.init:
      // ----------------------------------------------------------------------
      // The [RootIsolateToken] is required for
      // [BackgroundIsolateBinaryMessenger.ensureInitialized] and must be
      // obtained on the root isolate and passed into the background isolate via
      // a [SendPort].
      // ----------------------------------------------------------------------
        RootIsolateToken rootIsolateToken =
        command.args?[0] as RootIsolateToken;
        // ----------------------------------------------------------------------
        // [BackgroundIsolateBinaryMessenger.ensureInitialized] for each
        // background isolate that will use plugins. This sets up the
        // [BinaryMessenger] that the Platform Channels will communicate with on
        // the background isolate.
        // ----------------------------------------------------------------------
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
        _interpreter = Interpreter.fromAddress(command.args?[1] as int);
        _labels = command.args?[2] as List<String>;
        _sendPort.send(const _Command(_Codes.ready));
      case _Codes.detect:
        _sendPort.send(const _Command(_Codes.busy));
        _convertCameraImage(command.args?[0] as CameraImage);
      default:
        debugPrint('_DetectorService unrecognized command ${command.code}');
    }
  }

  void _convertCameraImage(CameraImage cameraImage) {
    var preConversionTime = DateTime.now().millisecondsSinceEpoch;

    convertCameraImageToImage(cameraImage).then((image) {
      if (image != null) {
        if (Platform.isAndroid) {
          image = image_lib.copyRotate(image, angle: 90);
        }

        final results = analyseImage(image, preConversionTime);
        _sendPort.send(_Command(_Codes.result, args: [results]));
      }
    });
  }

  Map<String, dynamic> analyseImage(
      image_lib.Image? image, int preConversionTime) {

    final imageInput = image_lib.copyResize(
      image!,
      width: mlModelInputSize,
      height: mlModelInputSize,
    );

    // Creating matrix representation, [300, 300, 3]
    final imageMatrix = List.generate(
      imageInput.height,
          (y) => List.generate(
        imageInput.width,
            (x) {
          final pixel = imageInput.getPixel(x, y);
          return [pixel.r, pixel.g, pixel.b];
        },
      ),
    );

    final output = _runInference(imageMatrix);

    // Location
    final locationsRaw = output.first.first as List<List<double>>;

    final List<Rect> locations = locationsRaw
        .map((list) => list.map((value) => (value * mlModelInputSize)).toList())
        .map((rect) => Rect.fromLTRB(rect[1], rect[0], rect[3], rect[2]))
        .toList();

    // Classes
    final classesRaw = output.elementAt(1).first as List<double>;
    final classes = classesRaw.map((value) => value.toInt()).toList();

    // Scores
    final scores = output.elementAt(2).first as List<double>;

    // Number of detections
    final numberOfDetectionsRaw = output.last.first as double;
    final numberOfDetections = numberOfDetectionsRaw.toInt();

    final List<String> classification = [];
    for (var i = 0; i < numberOfDetections; i++) {
      classification.add(_labels![classes[i]]);
    }

    /// Generate recognitions
    List<Recognition> recognitions = [];

    // Calculate distance between first detected object and subsequent ones
    if (numberOfDetections > 0) {
      Rect firstBoundingBox = locations[0];
      Point<double> firstCenterPoint = Point<double>(
        firstBoundingBox.left + firstBoundingBox.width / 2,
        firstBoundingBox.top + firstBoundingBox.height / 2,
      );

      for (int i = 0; i < numberOfDetections; i++) {
        // Prediction score
        var score = (scores[i] * 100).round() / 100.0;
        // Label string
        var label = classification[i];

        // Add approximate position determination for each recognition
        if (score > confidence ) {
          recognitions.add(
            Recognition(i, label, score, locations[i]),
          );
        }

        // Print center points for each recognition
        recognitions.forEach((recognition) {
          Rect boundingBox = recognition.location;

          String approximatePosition = determineApproximatePosition(
            boundingBox,
            // centerPoint, // Pass the centerPoint here
            image!.width, // Assuming image width is available
            image!.height, // Assuming image height is available
          );
          recognition.approximatePosition = approximatePosition;


          Point<double> centerPoint = Point<double>(
            boundingBox.left + boundingBox.width / 2,
            boundingBox.top + boundingBox.height / 2,
          );

          // Calculate distance between first detected object and current one
          double distance = calculateDistance(firstCenterPoint, centerPoint);
          print("Distance between first object and object $i: $distance");

          recognition.approximateDistance = distance;

          print(recognition.centerPoint);
          print(recognition.approximatePosition);
          print(recognition.approximateDistance);
        });
      }
    }





    return {
      "recognitions": recognitions,
      "stats": <String, String>{
        'Frame': '${image.width} X ${image.height}',
        'Approximate Positions': recognitions
            .map((recognition) => "${recognition.label} position - (${recognition.approximatePosition}) score -  (${recognition.score}) distance - (${(recognition.approximateDistance)!/10}))")
            .join(', ')
      },
    };
  }



  /// Object detection main function
  /// For ssd
  /// The model expects a 4D tensor with dimensions [1, 300, 300, 3], where 1 is the batch size, and 300x300x3 is the size of the input image.
  List<List<Object>> _runInference(
      List<List<List<num>>> imageMatrix,
      ) {

    final input = [imageMatrix];
    final output = {

      0: [List<List<num>>.filled(10, List<num>.filled(4, 0))],
      1: [List<num>.filled(10, 0)],
      2: [List<num>.filled(10, 0)],
      3: [0.0],
    };

    _interpreter!.runForMultipleInputs([input], output);
    return output.values.toList();
  }

  // Function to calculate the distance between two points in 2D space
  double calculateDistance(Point<double> point1, Point<double> point2) {
    double dx = point2.x - point1.x;
    double dy = point2.y - point1.y;
    return sqrt(dx * dx + dy * dy);
  }


  String determineApproximatePosition(Rect boundingBox, int imageWidth, int imageHeight) {
    // Calculate bounding box center point
    double centerX = boundingBox.left + boundingBox.width / 2;
    double centerY = boundingBox.top + boundingBox.height / 2;

    // Tolerance for "In-Front" based on bounding box size and image size
    double toleranceX = boundingBox.width * 0.1; // 40% of bounding box width
    double toleranceY = boundingBox.height * 0.1; // 40% of bounding box height

    // Check if center point is close enough to image center (considering tolerances)
    if (centerX.abs() < imageWidth / 2 + toleranceX && centerY.abs() < imageHeight / 2 + toleranceY) {
      return "In-Front";
    }

    bool isTopHalf = boundingBox.top < imageHeight / 2;
    bool isLeftHalf = boundingBox.left < imageWidth / 2;

    // Determine approximate position based on quadrant and half
    if (isTopHalf) {
      if (isLeftHalf) {
        return "Front-Left";
      } else {
        return "Front-Right";
      }
    } else {
      if (isLeftHalf) {
        return "Behind-Left";
      } else {
        return "Behind-Right";
      }
    }
  }



}
