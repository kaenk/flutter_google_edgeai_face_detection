import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_face_detector/flutter_face_detector.dart';

void main() => runApp(const MyApp());

/// 连接对结构，参考 FaceOverlay.swift 的实现
class Connection {
  final int start;
  final int end;
  const Connection(this.start, this.end);
}

/// 连接线组，包含颜色和连接对列表
class LineConnection {
  final Color color;
  final List<Connection> connections;
  const LineConnection({required this.color, required this.connections});
}

/// MediaPipe 面部关键点连接定义
class FaceLandmarkConnections {
  // 面部轮廓连接（Face Oval）
  static List<Connection> faceOvalConnections() {
    return [
      Connection(10, 338),
      Connection(338, 297),
      Connection(297, 332),
      Connection(332, 284),
      Connection(284, 251),
      Connection(251, 389),
      Connection(389, 356),
      Connection(356, 454),
      Connection(454, 323),
      Connection(323, 361),
      Connection(361, 288),
      Connection(288, 397),
      Connection(397, 365),
      Connection(365, 379),
      Connection(379, 378),
      Connection(378, 400),
      Connection(400, 377),
      Connection(377, 152),
      Connection(152, 148),
      Connection(148, 176),
      Connection(176, 149),
      Connection(149, 150),
      Connection(150, 136),
      Connection(136, 172),
      Connection(172, 58),
      Connection(58, 132),
      Connection(132, 93),
      Connection(93, 234),
      Connection(234, 127),
      Connection(127, 162),
      Connection(162, 21),
      Connection(21, 54),
      Connection(54, 103),
      Connection(103, 67),
      Connection(67, 109),
      Connection(109, 10),
    ];
  }

  // 右眉毛连接（Right Eyebrow）
  static List<Connection> rightEyebrowConnections() {
    return [
      Connection(107, 66),
      Connection(66, 105),
      Connection(105, 63),
      Connection(63, 70),
      Connection(70, 46),
      Connection(46, 53),
      Connection(53, 52),
      Connection(52, 65),
      Connection(65, 55),
    ];
  }

  // 左眉毛连接（Left Eyebrow）
  static List<Connection> leftEyebrowConnections() {
    return [
      Connection(336, 296),
      Connection(296, 334),
      Connection(334, 293),
      Connection(293, 300),
      Connection(300, 276),
      Connection(276, 283),
      Connection(283, 282),
      Connection(282, 295),
      Connection(295, 285),
    ];
  }

  // 右眼连接（Right Eye）
  static List<Connection> rightEyeConnections() {
    return [
      Connection(33, 7),
      Connection(7, 163),
      Connection(163, 144),
      Connection(144, 145),
      Connection(145, 153),
      Connection(153, 154),
      Connection(154, 155),
      Connection(155, 133),
      Connection(133, 173),
      Connection(173, 157),
      Connection(157, 158),
      Connection(158, 159),
      Connection(159, 160),
      Connection(160, 161),
      Connection(161, 246),
      Connection(246, 33),
    ];
  }

  // 左眼连接（Left Eye）
  static List<Connection> leftEyeConnections() {
    return [
      Connection(362, 382),
      Connection(382, 381),
      Connection(381, 380),
      Connection(380, 374),
      Connection(374, 373),
      Connection(373, 390),
      Connection(390, 249),
      Connection(249, 263),
      Connection(263, 466),
      Connection(466, 388),
      Connection(388, 387),
      Connection(387, 386),
      Connection(386, 385),
      Connection(385, 384),
      Connection(384, 398),
      Connection(398, 362),
    ];
  }

  // 嘴唇连接（Lips）
  static List<Connection> lipsConnections() {
    return [
      // 外唇 - 上嘴唇上方（从左到右）
      Connection(61, 185),
      Connection(185, 40),
      Connection(40, 39),
      Connection(39, 37),
      Connection(37, 0),
      Connection(0, 267),
      Connection(267, 269),
      Connection(269, 270),
      Connection(270, 409),
      Connection(409, 306),
      // 外唇 - 上嘴唇下方（从右到左）
      Connection(306, 308),
      Connection(308, 415),
      Connection(415, 310),
      Connection(310, 311),
      Connection(311, 312),
      Connection(312, 13),
      Connection(13, 82),
      Connection(82, 81),
      Connection(81, 80),
      Connection(80, 191),
      Connection(191, 62),
      // 闭合外唇
      // 61 146 91 181 84 17 314 405 321 375 306
      Connection(61, 146),
      Connection(146, 91),
      Connection(91, 181),
      Connection(181, 84),
      Connection(84, 17),
      Connection(17, 314),
      Connection(314, 405),
      Connection(405, 321),
      Connection(321, 375),
      Connection(375, 306),
      // 内唇
// 下嘴唇上方 左起
// 78 95 88 178 87 14 317 402 318 324 308
      Connection(78, 78),
      Connection(78, 95),
      Connection(95, 88),
      Connection(88, 178),
      Connection(178, 87),
      Connection(87, 14),
      Connection(14, 317),
      Connection(317, 402),
      Connection(402, 318),
      Connection(318, 324),
      Connection(324, 308),
      // Connection(308, 78),
    ];
  }
}

/// 人脸关键点绘制器
/// 参考 FaceOverlay.swift 的实现，使用连接对绘制面部特征
class FaceLandmarkPainter extends CustomPainter {
  final List<List<double>> landmarks;
  final bool showConnections;
  final bool showPoints;
  final Animation<double>? highlightAnimation;
  final int highlightWindowSize;

  FaceLandmarkPainter({
    required this.landmarks,
    this.showConnections = true,
    this.showPoints = true,
    this.highlightAnimation,
    this.highlightWindowSize = 36,
    Listenable? repaint,
  }) : super(repaint: repaint ?? highlightAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    // MediaPipe 返回的坐标是归一化的（0-1），需要转换为绘制坐标
    final transformedPoints = landmarks.map((point) {
      return Offset(
        point[0] * size.width,
        point[1] * size.height,
      );
    }).toList();

    final leftEyeConnectionsColor = Colors.cyan.withValues(alpha: 0.6);

    // 定义连接线组，参考 FaceOverlay.swift 的颜色方案
    final lineConnections = <LineConnection>[
      LineConnection(
        color: leftEyeConnectionsColor, // 类似 faceOvalConnectionsColor
        connections: FaceLandmarkConnections.faceOvalConnections(),
      ),
      LineConnection(
        color: leftEyeConnectionsColor, // 类似 rightEyebrowConnectionsColor
        connections: FaceLandmarkConnections.rightEyebrowConnections(),
      ),
      LineConnection(
        color: leftEyeConnectionsColor, // 类似 leftEyebrowConnectionsColor
        connections: FaceLandmarkConnections.leftEyebrowConnections(),
      ),
      LineConnection(
        color: leftEyeConnectionsColor, // 类似 rightEyeConnectionsColor
        connections: FaceLandmarkConnections.rightEyeConnections(),
      ),
      LineConnection(
        color: leftEyeConnectionsColor, // 类似 leftEyeConnectionsColor
        connections: FaceLandmarkConnections.leftEyeConnections(),
      ),
      LineConnection(
        color: leftEyeConnectionsColor, // 类似 lipsConnectionsColor
        connections: FaceLandmarkConnections.lipsConnections(),
      ),
    ];

    final featureScale = _resolveFeatureScale(transformedPoints);

    // 绘制连接线
    if (showConnections) {
      _drawLines(
        canvas,
        transformedPoints,
        lineConnections,
        featureScale,
      );
    }

    // 绘制关键点
    if (showPoints) {
      _drawPoints(
        canvas,
        transformedPoints,
        featureScale,
      );
    }
  }

  /// 绘制连接线，参考 FaceOverlay.swift 的 drawLines 方法
  void _drawLines(
    Canvas canvas,
    List<Offset> points,
    List<LineConnection> lineConnections,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final lineConnection in lineConnections) {
      paint.color = lineConnection.color;
      final path = Path();
      bool isFirst = true;

      for (final connection in lineConnection.connections) {
        if (connection.start >= points.length ||
            connection.end >= points.length) {
          continue;
        }

        final start = points[connection.start];
        final end = points[connection.end];

        if (isFirst) {
          path.moveTo(start.dx, start.dy);
          isFirst = false;
        }
        path.lineTo(end.dx, end.dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  /// 绘制关键点，参考 FaceOverlay.swift 的 drawDots 方法
  void _drawPoints(
    Canvas canvas,
    List<Offset> points,
    double pointRadius,
  ) {
    final highlightSet = _currentHighlightIndices(points.length);
    final pulseValue = _highlightPulse();
    final baseColor = Colors.cyan.withValues(alpha: 0.4);
    final glowColor = Colors.white.withValues(alpha: 0.7);
    final pointPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      pointPaint.color = highlightSet.contains(i)
          ? Color.lerp(baseColor, glowColor, pulseValue) ?? baseColor
          : baseColor;
      final dotRect = Rect.fromCircle(
        center: point,
        radius: pointRadius,
      );
      canvas.drawOval(dotRect, pointPaint);
    }
  }

  double _resolveFeatureScale(List<Offset> points) {
    const fallbackScale = 0.5;
    const minScale = 0.2;
    const maxScale = 1.0;
    const referenceDistance = 50.0;

    if (points.length <= 473) {
      return fallbackScale;
    }

    final leftPupil = points[468];
    final rightPupil = points[473];
    final distance = (leftPupil - rightPupil).distance;
    if (distance <= 0) {
      return fallbackScale;
    }

    final normalized = (distance / referenceDistance).clamp(minScale, maxScale);
    return normalized;
  }

  Set<int> _currentHighlightIndices(int totalPoints) {
    if (highlightAnimation == null ||
        totalPoints == 0 ||
        highlightWindowSize <= 0) {
      return const <int>{};
    }

    final window = math.min(highlightWindowSize, totalPoints);
    final segments = math.max(1, (totalPoints / window).ceil());
    final normalized = highlightAnimation!.value.clamp(0.0, 0.9999);
    final segmentIndex = (normalized * segments).floor();
    final start = segmentIndex * window;
    final end = math.min(start + window, totalPoints);

    return {
      for (var i = start; i < end; i++) i,
    };
  }

  double _highlightPulse() {
    if (highlightAnimation == null) {
      return 0.0;
    }
    return 0.5 - 0.5 * math.cos(highlightAnimation!.value * 2 * math.pi);
  }

  @override
  bool shouldRepaint(FaceLandmarkPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.showConnections != showConnections ||
        oldDelegate.showPoints != showPoints ||
        oldDelegate.highlightWindowSize != highlightWindowSize;
  }
}

/// 带关键点绘制的图片组件
class LandmarkImage extends StatelessWidget {
  final Uint8List imageBytes;
  final List<List<double>>? landmarks;
  final bool enableHighlightAnimation;

  const LandmarkImage({
    super.key,
    required this.imageBytes,
    this.landmarks,
    this.enableHighlightAnimation = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Image.memory(
          imageBytes,
          fit: BoxFit.cover,
        ),
        if (landmarks != null && landmarks!.isNotEmpty)
          Positioned.fill(
            child: AnimatedLandmarkOverlay(
              landmarks: landmarks!,
              enableAnimation: enableHighlightAnimation,
            ),
          ),
      ],
    );
  }
}

class AnimatedLandmarkOverlay extends StatefulWidget {
  final List<List<double>> landmarks;
  final bool showConnections;
  final bool showPoints;
  final bool enableAnimation;

  const AnimatedLandmarkOverlay({
    super.key,
    required this.landmarks,
    this.showConnections = true,
    this.showPoints = true,
    this.enableAnimation = true,
  });

  @override
  State<AnimatedLandmarkOverlay> createState() =>
      _AnimatedLandmarkOverlayState();
}

class _AnimatedLandmarkOverlayState extends State<AnimatedLandmarkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.enableAnimation) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedLandmarkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableAnimation != oldWidget.enableAnimation) {
      if (widget.enableAnimation) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FaceLandmarkPainter(
        landmarks: widget.landmarks,
        showConnections: widget.showConnections,
        showPoints: widget.showPoints,
        highlightAnimation: widget.enableAnimation ? _controller : null,
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _detector = FlutterFaceDetector();

  double _confidenceValue = 0.0;
  String _inferenceTime = '0ms';
  Uint8List? _imageBytes;

  // 關鍵點檢測相關狀態
  List<List<List<double>>>? _landmarks;
  int _faceCount = 0;
  String _landmarkInferenceTime = '0ms';
  bool _isLandmarkMode = false;

  Future<void> _pickImageAndDetect() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _confidenceValue = 0;
      _landmarks = null;
      _faceCount = 0;
    });

    try {
      if (_isLandmarkMode) {
        // 執行關鍵點檢測
        final Map<String, dynamic> result =
            await _detector.faceLandmarkDetectionFromImage(bytes);

        final raw = result['confidence']?.toString() ?? '0';
        final cleaned = raw.replaceAll('%', '').trim();
        final value = double.tryParse(cleaned);
        final confidence = (value ?? 0.0) / (raw.contains('%') ? 100 : 1);

        // 解析關鍵點數據
        List<List<List<double>>> landmarks = [];
        if (result['landmarks'] != null) {
          final landmarksData = result['landmarks'] as List;
          for (var faceLandmarks in landmarksData) {
            if (faceLandmarks is List) {
              List<List<double>> facePoints = [];
              for (var point in faceLandmarks) {
                if (point is List) {
                  facePoints
                      .add(point.map((e) => (e as num).toDouble()).toList());
                }
              }
              landmarks.add(facePoints);
            }
          }
        }

        setState(() {
          _confidenceValue = confidence.clamp(0.0, 1.0);
          _landmarkInferenceTime = result['inferenceTime']?.toString() ?? 'N/A';
          _landmarks = landmarks;
          _faceCount = result['faceCount'] as int? ?? 0;
        });
      } else {
        // 執行普通臉部檢測
        final Map<String, dynamic> result =
            await _detector.faceDetectionFromImage(bytes);

        final raw = result['confidence']?.toString() ?? '0';
        final cleaned = raw.replaceAll('%', '').trim();
        final value = double.tryParse(cleaned);
        final confidence = (value ?? 0.0) / (raw.contains('%') ? 100 : 1);

        setState(() {
          _confidenceValue = confidence.clamp(0.0, 1.0);
          _inferenceTime = result['inferenceTime']?.toString() ?? 'N/A';
        });
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Center(
            child: Column(
              children: [
                SizedBox(height: 80),
                // 頭像顯示卡片
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      if (_imageBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _isLandmarkMode &&
                                  _landmarks != null &&
                                  _landmarks!.isNotEmpty
                              ? LandmarkImage(
                                  imageBytes: _imageBytes!,
                                  landmarks: _landmarks!.first, // 显示第一张脸的关键点
                                )
                              : Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.cover,
                                ),
                        )
                      else
                        Container(
                          width: 300,
                          height: 330,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade200,
                          ),
                          child: const Icon(Icons.person_outline,
                              size: 100, color: Colors.grey),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Confidence：${(_confidenceValue * 100).toStringAsFixed(2)}%',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        _isLandmarkMode
                            ? 'Inference Time：$_landmarkInferenceTime'
                            : 'Inference Time：$_inferenceTime',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (_isLandmarkMode && _faceCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '检测到 $_faceCount 张人脸，共 ${_landmarks?.first.length ?? 0} 个关键点',
                            style: const TextStyle(
                                fontSize: 14, color: Colors.blue),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 模式切換開關
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('普通检测', style: TextStyle(fontSize: 14)),
                    Switch(
                      value: _isLandmarkMode,
                      onChanged: (value) {
                        setState(() {
                          _isLandmarkMode = value;
                          _landmarks = null;
                          _faceCount = 0;
                        });
                      },
                    ),
                    const Text('关键点检测', style: TextStyle(fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 20),

                // 選擇照片按鈕
                ElevatedButton.icon(
                  onPressed: _pickImageAndDetect,
                  icon: Icon(_isLandmarkMode
                      ? Icons.face_outlined
                      : Icons.photo_library_outlined),
                  label: Text(_isLandmarkMode ? '选择照片进行关键点检测' : '选择照片进行识别'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(220, 50),
                    backgroundColor: _isLandmarkMode
                        ? Colors.purple.shade600
                        : Colors.blue.shade600,
                  ),
                ),
                const SizedBox(height: 20),

                // 顯示關鍵點信息
                if (_isLandmarkMode &&
                    _landmarks != null &&
                    _landmarks!.isNotEmpty)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '关键点信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(_landmarks!.length, (faceIndex) {
                            final faceLandmarks = _landmarks![faceIndex];
                            return ExpansionTile(
                              title: Text(
                                  '人脸 ${faceIndex + 1} (${faceLandmarks.length} 个关键点)'),
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: faceLandmarks.length,
                                    itemBuilder: (context, index) {
                                      final point = faceLandmarks[index];
                                      return Container(
                                        margin: const EdgeInsets.all(4),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.blue.shade200),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '點 ${index + 1}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'X: ${point[0].toStringAsFixed(3)}',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                            Text(
                                              'Y: ${point[1].toStringAsFixed(3)}',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                            if (point.length > 2)
                                              Text(
                                                'Z: ${point[2].toStringAsFixed(3)}',
                                                style: const TextStyle(
                                                    fontSize: 11),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
