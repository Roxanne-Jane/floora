import 'package:florafolium_app/splashscreen.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:logger/logger.dart';
import 'dart:ui'; // Import for BackdropFilter
import 'result_screen.dart';

List<CameraDescription> cameras = [];
var logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const FloraFoliumApp());
}

class FloraFoliumApp extends StatelessWidget {
  const FloraFoliumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  XFile? imageFile;
  final ImagePicker _picker = ImagePicker();
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoading = false; // Loading state variable

  @override
  void initState() {
    super.initState();
    controller = CameraController(cameras[0], ResolutionPreset.high);
    controller?.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/leafv7.tflite');
      _labels = await _loadLabels('assets/labels.txt');
      logger.i("Model and labels loaded successfully.");
    } catch (e) {
      logger.e("Failed to load model or labels: $e");
    }
  }

  Future<List<String>> _loadLabels(String filePath) async {
    final labelsData = await rootBundle.loadString(filePath);
    return labelsData.split('\n').where((label) => label.isNotEmpty).toList();
  }

  Future<void> captureImage() async {
    if (controller?.value.isInitialized == true &&
        !controller!.value.isTakingPicture) {
      try {
        XFile picture = await controller!.takePicture();
        setState(() => imageFile = picture);
        if (mounted) _navigateToResult(picture);
      } catch (e) {
        logger.e("Error capturing image: $e");
      }
    }
  }

  Future<void> pickImage() async {
    try {
      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => imageFile = pickedFile);
        if (mounted) _navigateToResult(pickedFile);
      }
    } catch (e) {
      logger.e("Error picking image: $e");
    }
  }

  Future<void> _navigateToResult(XFile image) async {
    try {
      setState(() {
        _isLoading = true; // Show loading indicator
      });
      var result = await classifyImage(image.path);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              plantName: result,
              imagePath: image.path,
              confidence: 95.0, // Dummy confidence for example
            ),
          ),
        );
      }
    } catch (e) {
      logger.e("Error classifying image: $e");
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
    }
  }

  Future<String> classifyImage(String imagePath) async {
    try {
      Uint8List imageBytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return "Error decoding image.";

      img.Image resizedImage = img.copyResize(image, width: 256, height: 256);
      var input = List<double>.filled(1 * 256 * 256 * 3, 0.0);
      int pixelIndex = 0;
      for (int y = 0; y < 256; y++) {
        for (int x = 0; x < 256; x++) {
          var pixel = resizedImage.getPixel(x, y);
          input[pixelIndex++] = img.getRed(pixel) / 255.0;
          input[pixelIndex++] = img.getGreen(pixel) / 255.0;
          input[pixelIndex++] = img.getBlue(pixel) / 255.0;
        }
      }

      var reshapedInput = _reshape(input, 1, 256, 256, 3);

      if (_interpreter == null) return "Model not loaded.";

      // Update the output shape to 45
      var output = List.generate(1, (_) => List.filled(45, 0.0));
      _interpreter!.run(reshapedInput, output);
      var probabilities = output[0];

      final maxProbabilityIndex = probabilities.indexWhere((element) =>
          element == probabilities.reduce((a, b) => a > b ? a : b));

      return maxProbabilityIndex >= 0 && maxProbabilityIndex < _labels.length
          ? _labels[maxProbabilityIndex]
          : "Classification failed.";
    } catch (e) {
      logger.e("Error classifying image: $e");
      return "Error occurred during classification.";
    }
  }

  List<List<List<List<double>>>> _reshape(
      List<double> input, int batch, int height, int width, int channels) {
    return List.generate(batch, (b) {
      return List.generate(height, (h) {
        return List.generate(width, (w) {
          return List.generate(channels, (c) {
            return input[(b * height * width * channels) +
                (h * width * channels) +
                (w * channels) +
                c];
          });
        });
      });
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  void _showModal() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Menu',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('About App'),
                onTap: () {
                  Navigator.pop(context);
                  // Handle the About action here
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('About App'),
                        content: const Text(
                          'Florafolium is your ultimate plant leaf identification and classification app, designed for nature enthusiasts, gardeners, and anyone interested in plants. '
                          'Using advanced image recognition technology, Florafolium makes it easy to identify plants with ease. '
                          'Simply take a photo or upload an image, and the app will provide you with detailed information about the plant species. '
                          'It will also tell you if the plant is Edible, Medicinal, or Toxic.',
                          textAlign: TextAlign.justify, // Justify the text
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('language'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              // Add more options as needed
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFFD5E8D4),
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 350, // Adjust height as needed
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: _buildCustomHamburgerIcon(), // Custom hamburger icon
            onPressed: _showModal, // Show modal on tap
          ),
        ],
      ),
      body: Stack(
        // Use Stack to overlay loading indicator
        children: [
          SingleChildScrollView(
            child: Container(
              color: Color(0xFFD5E8D4),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: controller?.value.isInitialized == true
                            ? CameraPreview(controller!)
                            : const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconContainer(
                          iconPath: 'assets/upload.png',
                          onPressed: pickImage,
                        ),
                        IconContainer(
                          iconPath: 'assets/startcamera.png',
                          onPressed: captureImage,
                        ),
                        IconContainer(
                          iconPath: 'assets/tips.png',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: const Text('Snap Tips'),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          '1. FOCUS ON A SINGLE LEAF.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Take a picture of just one leaf, so the app won’t get confused by other plants around it.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '2. CAPTURE IN GOOD LIGHTING.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Take the photo in natural daylight to ensure clear image details.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '3. CENTER THE LEAF.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Place the leaf in the center of the screen, so the app can easily identify it. Make sure the whole leaf is visible.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '4. HOLD STEADY TO AVOID BLURRY PHOTOS.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Keep your phone steady when taking the picture, so it doesn’t come out blurry.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '5. AVOID WET OR DIRTY LEAVES.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Make sure the leaf is clean and dry for better visibility of its texture, color, and structure.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '6. BACKGROUND MATTERS.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Use a plain background to ensure the leaf stands out in the image.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '7. CAPTURE DIFFERENT ANGLES.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Try different angles to capture all the details of the leaf.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '8. KEEP THE FRAME CLEAR.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 16.0),
                                          child: Text(
                                            'Make sure there’s nothing else in the background, like other plants or your hand, to avoid confusing the app.',
                                            textAlign: TextAlign.justify,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                      ],
                                    ),
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                        child: const Text('Close'),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        }),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Display loading indicator with blurred background if processing
          if (_isLoading)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0), // Blur effect
              child: Container(
                color: Colors.black54, // Semi-transparent background
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      const Text(
                        "Please wait...",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomHamburgerIcon() {
    return Container(
      padding: const EdgeInsets.all(10.0), // Padding around the icon
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(height: 4, width: 25, color: Colors.green), // Top bar
          const SizedBox(height: 4),
          Container(height: 4, width: 25, color: Colors.green), // Middle bar
          const SizedBox(height: 4),
          Container(height: 4, width: 25, color: Colors.green), // Bottom bar
        ],
      ),
    );
  }
}

class IconContainer extends StatelessWidget {
  final String iconPath;
  final VoidCallback onPressed;

  const IconContainer(
      {super.key, required this.iconPath, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 4),
          ),
        ],
        color: Colors.white,
      ),
      child: IconButton(
        icon: Image.asset(iconPath),
        iconSize: 50,
        onPressed: onPressed,
      ),
    );
  }
} 