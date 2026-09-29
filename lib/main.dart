import 'dart:convert';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color ink = Color(0xFF102A43);
const Color mint = Color(0xFF19C7A3);
const Color paper = Color(0xFFF5F8FA);

late SharedPreferences prefs;
late List<CameraDescription> cams;

Map<String, dynamic> db = {};
int fails = 0;

void seedDb() {
  if (db.isNotEmpty) return;

  db = {
    '9876500001': {
      'name': 'Aarav Sharma',
      'bank': 'Demo Bank A',
      'balance': 25000.0,
      'face': null,
      'fp': false,
      'tx': <Map<String, dynamic>>[],
    },
    '9876500002': {
      'name': 'Diya Patil',
      'bank': 'Demo Bank A',
      'balance': 30000.0,
      'face': null,
      'fp': false,
      'tx': <Map<String, dynamic>>[],
    },
    '9876500003': {
      'name': 'Rohan Mehta',
      'bank': 'Demo Bank B',
      'balance': 35000.0,
      'face': null,
      'fp': false,
      'tx': <Map<String, dynamic>>[],
    },
    '9876500004': {
      'name': 'Sneha Kulkarni',
      'bank': 'Demo Bank B',
      'balance': 40000.0,
      'face': null,
      'fp': false,
      'tx': <Map<String, dynamic>>[],
    },
    '9876500005': {
      'name': 'Vikram Singh',
      'bank': 'Demo Bank A',
      'balance': 45000.0,
      'face': null,
      'fp': false,
      'tx': <Map<String, dynamic>>[],
    },
    '9876500006': {
      'name': 'Ananya Rao',
      'bank': 'Demo Bank B',
      'balance': 50000.0,
      'face': null,
      'fp': false,
      'tx': <Map<String, dynamic>>[],
    },
  };
}

Future<void> saveDb() async {
  await prefs.setString('db', jsonEncode(db));
}

void loadDb() {
  final raw = prefs.getString('db');

  if (raw == null || raw.isEmpty) {
    seedDb();
    return;
  }

  try {
    final decoded = jsonDecode(raw);

    if (decoded is Map) {
      db = Map<String, dynamic>.from(decoded);
    } else {
      seedDb();
    }
  } catch (_) {
    seedDb();
  }
}

Map<String, dynamic>? findUser(String mobile) {
  final value = db[mobile];

  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return null;
}

/// Creates a demo-level face signature.
///
/// Important:
/// google_mlkit_face_detection performs FACE DETECTION, not biometric
/// face recognition. Therefore this is intentionally a lightweight
/// consistency check using detected face geometry and head position.
/// It is suitable for this demo, but is NOT production banking security.
List<double>? faceSignature(Face face) {
  final box = face.boundingBox;

  if (box.width < 60 || box.height < 60) {
    return null;
  }

  if (box.width <= 0 || box.height <= 0) {
    return null;
  }

  final yaw = face.headEulerAngleY ?? 0.0;
  final roll = face.headEulerAngleZ ?? 0.0;

  // Don't accept a face that is turned too far.
  if (yaw.abs() > 25 || roll.abs() > 25) {
    return null;
  }

  final aspectRatio = box.width / box.height;

  // Normalized values make the signature independent of camera resolution.
  final normalizedAspect = aspectRatio.clamp(0.50, 1.20);
  final normalizedYaw = (yaw / 25.0).clamp(-1.0, 1.0);
  final normalizedRoll = (roll / 25.0).clamp(-1.0, 1.0);

  // Optional classification values.
  // They are not required, because ML Kit may return null.
  final smile = face.smilingProbability ?? 0.0;
  final leftEye = face.leftEyeOpenProbability ?? 0.0;
  final rightEye = face.rightEyeOpenProbability ?? 0.0;

  return [
    normalizedAspect,
    normalizedYaw,
    normalizedRoll,
    smile.clamp(0.0, 1.0),
    leftEye.clamp(0.0, 1.0),
    rightEye.clamp(0.0, 1.0),
  ];
}

double _difference(List<double> a, List<double> b) {
  final length = min(a.length, b.length);

  if (length == 0) return double.infinity;

  double total = 0;

  for (int i = 0; i < length; i++) {
    total += (a[i] - b[i]).abs();
  }

  return total / length;
}

/// Demo-level comparison.
///
/// The threshold is intentionally tolerant because the same person's
/// face can produce slightly different geometry between two camera shots.
bool sameFace(List<double> registered, List<double> current) {
  if (registered.isEmpty || current.isEmpty) {
    return false;
  }

  final difference = _difference(registered, current);

  return difference <= 0.30;
}

void msg(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

Widget btn(
  String text,
  VoidCallback? onPressed, {
  IconData? icon,
}) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward),
      label: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: mint,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
  );
}

class Shell extends StatelessWidget {
  final String title;
  final Widget child;
  final bool back;

  const Shell({
    super.key,
    required this.title,
    required this.child,
    this.back = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        automaticallyImplyLeading: back,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: child,
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  prefs = await SharedPreferences.getInstance();

  try {
    cams = await availableCameras();
  } catch (_) {
    cams = [];
  }

  loadDb();

  runApp(const CardlessATM());
}

class CardlessATM extends StatelessWidget {
  const CardlessATM({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cardless ATM',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: mint,
        ),
        fontFamily: 'Arial',
      ),
      home: const WelcomePage(),
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.atm,
                  color: Colors.white,
                  size: 42,
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'Cardless ATM',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Withdraw cash securely using face and fingerprint verification.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black54,
                ),
              ),

              const Spacer(),

              btn(
                'Get Started',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobilePage(register: false),
                    ),
                  );
                },
                icon: Icons.login,
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobilePage(register: true),
                    ),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text(
                  'Register Demo Account',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: ink),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Center(
                child: Text(
                  'Demo application • No real banking connection',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                  ),
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class MobilePage extends StatefulWidget {
  final bool register;

  const MobilePage({
    super.key,
    required this.register,
  });

  @override
  State<MobilePage> createState() => _MobilePageState();
}

class _MobilePageState extends State<MobilePage> {
  final controller = TextEditingController();

  bool loading = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> continueFlow() async {
    final mobile = controller.text.trim();

    if (mobile.length != 10 ||
        int.tryParse(mobile) == null) {
      msg(context, 'Enter a valid 10-digit mobile number.');
      return;
    }

    setState(() => loading = true);

    final user = findUser(mobile);

    if (widget.register) {
      if (user != null) {
        setState(() => loading = false);
        msg(context, 'Demo account already exists.');
        return;
      }

      // Create a demo account for an unknown mobile number.
      db[mobile] = {
        'name': 'Demo User',
        'bank': 'Demo Bank',
        'balance': 25000.0,
        'face': null,
        'fp': false,
        'tx': <Map<String, dynamic>>[],
      };

      await saveDb();

      if (!mounted) return;

      setState(() => loading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OTPPage(
            mobile: mobile,
            register: true,
          ),
        ),
      );

      return;
    }

    if (user == null) {
      setState(() => loading = false);
      msg(context, 'Demo account not found.');
      return;
    }

    final face = user['face'];
    final fp = user['fp'] == true;

    if (face == null || !fp) {
      setState(() => loading = false);
      msg(
        context,
        'Please register face and fingerprint first.',
      );
      return;
    }

    setState(() => loading = false);

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoginFacePage(
          mobile: mobile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: widget.register ? 'Register' : 'Login',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            Text(
              widget.register
                  ? 'Create your demo account'
                  : 'Welcome back',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Enter your registered mobile number to continue.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 30),

            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 20),

            btn(
              loading ? 'Please wait...' : 'Continue',
              loading ? null : continueFlow,
            ),

            const SizedBox(height: 20),

            if (!widget.register)
              const Center(
                child: Text(
                  'Demo numbers: 9876500001 to 9876500006',
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OTPPage extends StatefulWidget {
  final String mobile;
  final bool register;

  const OTPPage({
    super.key,
    required this.mobile,
    required this.register,
  });

  @override
  State<OTPPage> createState() => _OTPPageState();
}

class _OTPPageState extends State<OTPPage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void verify() {
    if (controller.text.trim() != '1234') {
      msg(context, 'Incorrect OTP. Demo OTP is 1234.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterFacePage(
          mobile: widget.mobile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: 'OTP Verification',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            const Icon(
              Icons.sms_outlined,
              size: 60,
              color: mint,
            ),

            const SizedBox(height: 20),

            const Text(
              'Enter OTP',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'OTP sent to ${widget.mobile}',
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 28),

            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'OTP',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Demo OTP: 1234',
              style: TextStyle(
                color: Colors.black45,
              ),
            ),

            const SizedBox(height: 24),

            btn(
              'Verify OTP',
              verify,
              icon: Icons.verified,
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterFacePage extends StatefulWidget {
  final String mobile;

  const RegisterFacePage({
    super.key,
    required this.mobile,
  });

  @override
  State<RegisterFacePage> createState() => _RegisterFacePageState();
}

class _RegisterFacePageState extends State<RegisterFacePage> {
  @override
  Widget build(BuildContext context) {
    return FacePage(
      title: 'Register Face',
      onResult: (signature) async {
        final user = findUser(widget.mobile);

        if (user == null) {
          if (mounted) {
            msg(context, 'Account not found.');
          }
          return;
        }

        user['face'] = signature;
        db[widget.mobile] = user;
        await saveDb();

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FingerprintPage(
              mobile: widget.mobile,
              registration: true,
            ),
          ),
        );
      },
    );
  }
}

class LoginFacePage extends StatelessWidget {
  final String mobile;

  const LoginFacePage({
    super.key,
    required this.mobile,
  });

  @override
  Widget build(BuildContext context) {
    return FacePage(
      title: 'Face Verification',
      onResult: (signature) async {
        final user = findUser(mobile);

        if (user == null) {
          if (context.mounted) {
            msg(context, 'Account not found.');
          }
          return;
        }

        final storedRaw = user['face'];

        if (storedRaw is! List) {
          if (context.mounted) {
            msg(context, 'Face registration is incomplete.');
          }
          return;
        }

        final stored = storedRaw
            .map((e) => (e as num).toDouble())
            .toList();

        if (!sameFace(stored, signature)) {
          if (context.mounted) {
            msg(
              context,
              'Face verification failed. Please look straight and try again.',
            );
          }
          return;
        }

        if (!context.mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FingerprintPage(
              mobile: mobile,
              registration: false,
            ),
          ),
        );
      },
    );
  }
}

class FacePage extends StatefulWidget {
  final String title;
  final Future<void> Function(List<double> signature) onResult;

  const FacePage({
    super.key,
    required this.title,
    required this.onResult,
  });

  @override
  State<FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<FacePage> {
  CameraController? camera;

  bool loading = true;
  bool scanning = false;

  String hint = 'Look straight at the camera';

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  Future<void> initializeCamera() async {
    try {
      if (cams.isEmpty) {
        if (mounted) {
          setState(() {
            loading = false;
            hint = 'No camera found on this device.';
          });
        }
        return;
      }

      CameraDescription selected = cams.first;

      for (final cam in cams) {
        if (cam.lensDirection == CameraLensDirection.front) {
          selected = cam;
          break;
        }
      }

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      camera = controller;

      setState(() {
        loading = false;
        hint = 'Look straight at the camera';
      });
    } catch (e) {
      debugPrint('CAMERA INITIALIZATION ERROR: $e');

      if (!mounted) return;

      setState(() {
        loading = false;
        hint = 'Camera could not be started. Please try again.';
      });
    }
  }

  Future<void> scanFace() async {
    if (scanning) return;

    final controller = camera;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      msg(context, 'Camera is not ready yet.');
      return;
    }

    setState(() {
      scanning = true;
      hint = 'Scanning face...';
    });

    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: false,
        enableClassification: true,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.10,
      ),
    );

    try {
      final XFile picture = await controller.takePicture();

      if (picture.path.isEmpty) {
        throw Exception('Camera returned an empty image path.');
      }

      final inputImage = InputImage.fromFilePath(picture.path);

      final faces = await detector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          scanning = false;
          hint = 'No face detected. Move closer and try again.';
        });
        return;
      }

      if (faces.length > 1) {
        setState(() {
          scanning = false;
          hint = 'Only one face should be visible.';
        });
        return;
      }

      final detectedFace = faces.first;

      final signature = faceSignature(detectedFace);

      if (signature == null) {
        setState(() {
          scanning = false;
          hint = 'Face is not clear. Look straight and try again.';
        });
        return;
      }

      setState(() {
        hint = 'Face detected successfully';
      });

      await detector.close();

      if (!mounted) return;

      await widget.onResult(signature);
    } catch (e, stack) {
      debugPrint('FACE SCAN ERROR: $e');
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        scanning = false;
        hint = 'Could not read the face. Try again.';
      });
    } finally {
      await detector.close();
    }
  }

  @override
  void dispose() {
    camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = camera;

    return Shell(
      title: widget.title,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 8),

            const Text(
              'Face verification',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: mint,
                        ),
                      )
                    : controller == null ||
                            !controller.value.isInitialized
                        ? const Center(
                            child: Icon(
                              Icons.no_photography_outlined,
                              color: Colors.white54,
                              size: 70,
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(controller),

                              Center(
                                child: Container(
                                  width: 230,
                                  height: 300,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(120),
                                    border: Border.all(
                                      color: mint,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),

                              if (scanning)
                                Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Keep your face inside the frame and look directly at the camera.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black45,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 14),

            btn(
              scanning ? 'Scanning...' : 'Scan Face',
              scanning || loading ? null : scanFace,
              icon: Icons.face,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class FingerprintPage extends StatefulWidget {
  final String mobile;
  final bool registration;

  const FingerprintPage({
    super.key,
    required this.mobile,
    required this.registration,
  });

  @override
  State<FingerprintPage> createState() => _FingerprintPageState();
}

class _FingerprintPageState extends State<FingerprintPage> {
  bool busy = false;

  Future<bool> authenticateFingerprint() async {
    final auth = LocalAuthentication();

    try {
      final supported = await auth.isDeviceSupported();

      if (!supported) {
        return false;
      }

      final canCheck = await auth.canCheckBiometrics;

      if (!canCheck) {
        return false;
      }

      final types = await auth.getAvailableBiometrics();

      if (types.isEmpty) {
        return false;
      }

      return await auth.authenticate(
        localizedReason: widget.registration
            ? 'Verify your fingerprint to complete registration'
            : 'Verify your fingerprint to login',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('FINGERPRINT ERROR: $e');
      return false;
    }
  }

  Future<void> continueFlow() async {
    if (busy) return;

    setState(() => busy = true);

    final authenticated = await authenticateFingerprint();

    if (!mounted) return;

    if (!authenticated) {
      setState(() => busy = false);

      msg(
        context,
        'Fingerprint verification failed or is not available on this device.',
      );

      return;
    }

    if (widget.registration) {
      final user = findUser(widget.mobile);

      if (user == null) {
        setState(() => busy = false);
        msg(context, 'Account not found.');
        return;
      }

      user['fp'] = true;

      db[widget.mobile] = user;

      await saveDb();

      if (!mounted) return;

      setState(() => busy = false);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => RegistrationCompletePage(
            mobile: widget.mobile,
          ),
        ),
        (route) => route.isFirst,
      );

      return;
    }

    if (!mounted) return;

    setState(() => busy = false);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardPage(
          mobile: widget.mobile,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: widget.registration
          ? 'Fingerprint Setup'
          : 'Fingerprint Verification',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                color: mint.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.fingerprint,
                size: 90,
                color: mint,
              ),
            ),

            const SizedBox(height: 30),

            Text(
              widget.registration
                  ? 'Register Fingerprint'
                  : 'Verify Fingerprint',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              widget.registration
                  ? 'Use your device fingerprint to complete demo registration.'
                  : 'Use your registered fingerprint to continue.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 15,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 36),

            btn(
              busy ? 'Verifying...' : 'Verify Fingerprint',
              busy ? null : continueFlow,
              icon: Icons.fingerprint,
            ),
          ],
        ),
      ),
    );
  }
}

class RegistrationCompletePage extends StatelessWidget {
  final String mobile;

  const RegistrationCompletePage({
    super.key,
    required this.mobile,
  });

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: 'Registration Complete',
      back: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: mint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 60,
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              'Registration Complete',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'Your demo account $mobile is ready.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 32),

            btn(
              'Go to Login',
              () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MobilePage(
                      register: false,
                    ),
                  ),
                  (route) => false,
                );
              },
              icon: Icons.login,
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final String mobile;

  const DashboardPage({
    super.key,
    required this.mobile,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? get user => findUser(widget.mobile);

  String money(dynamic value) {
    final number = (value as num?)?.toDouble() ?? 0;
    return '₹${number.toStringAsFixed(2)}';
  }

  Future<void> refresh() async {
    if (mounted) {
      setState(() {});
    }
  }

  void logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const WelcomePage(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = user;

    if (currentUser == null) {
      return const WelcomePage();
    }

    final balance =
        (currentUser['balance'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        title: const Text(
          'Cardless ATM',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Hello, ${currentUser['name']}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              '${currentUser['bank']} • ${widget.mobile}',
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Balance',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    money(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            btn(
              'Withdraw Cash',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WithdrawPage(
                      mobile: widget.mobile,
                    ),
                  ),
                ).then((_) => setState(() {}));
              },
              icon: Icons.payments_outlined,
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StatementPage(
                      mobile: widget.mobile,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text(
                'Mini Statement',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: ink),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WithdrawPage extends StatefulWidget {
  final String mobile;

  const WithdrawPage({
    super.key,
    required this.mobile,
  });

  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  final amountController = TextEditingController();

  bool processing = false;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  Future<void> withdraw() async {
    if (processing) return;

    final amount = double.tryParse(
      amountController.text.trim(),
    );

    if (amount == null ||
        amount < 100 ||
        amount % 100 != 0) {
      msg(
        context,
        'Enter an amount in multiples of ₹100.',
      );
      return;
    }

    if (amount > 20000) {
      msg(
        context,
        'Maximum demo withdrawal is ₹20,000.',
      );
      return;
    }

    final user = findUser(widget.mobile);

    if (user == null) {
      msg(context, 'Account not found.');
      return;
    }

    final balance =
        (user['balance'] as num?)?.toDouble() ?? 0.0;

    if (amount > balance) {
      msg(context, 'Insufficient balance.');
      return;
    }

    setState(() => processing = true);

    await Future.delayed(const Duration(milliseconds: 700));

    user['balance'] = balance - amount;

    final transactions = user['tx'];

    if (transactions is List) {
      transactions.insert(
        0,
        {
          'type': 'Withdrawal',
          'amount': amount,
          'date': DateTime.now().toIso8601String(),
        },
      );
    } else {
      user['tx'] = [
        {
          'type': 'Withdrawal',
          'amount': amount,
          'date': DateTime.now().toIso8601String(),
        },
      ];
    }

    db[widget.mobile] = user;

    await saveDb();

    if (!mounted) return;

    setState(() => processing = false);

    amountController.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text(
          'Withdrawal Successful',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '₹${amount.toStringAsFixed(2)} has been withdrawn.\n\nRemaining balance: ₹${(balance - amount).toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: 'Withdraw Cash',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            const Text(
              'Enter withdrawal amount',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Demo limit: ₹100 to ₹20,000 in multiples of ₹100.',
              style: TextStyle(
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 28),

            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 24),

            btn(
              processing ? 'Processing...' : 'Withdraw',
              processing ? null : withdraw,
              icon: Icons.payments,
            ),
          ],
        ),
      ),
    );
  }
}

class StatementPage extends StatelessWidget {
  final String mobile;

  const StatementPage({
    super.key,
    required this.mobile,
  });

  String formatDate(String raw) {
    try {
      final date = DateTime.parse(raw);

      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();

      return '$day/$month/$year';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = findUser(mobile);

    if (user == null) {
      return const Shell(
        title: 'Mini Statement',
        child: Center(
          child: Text('Account not found.'),
        ),
      );
    }

    final rawTx = user['tx'];

    final List<Map<String, dynamic>> transactions = [];

    if (rawTx is List) {
      for (final item in rawTx) {
        if (item is Map) {
          transactions.add(
            Map<String, dynamic>.from(item),
          );
        }
      }
    }

    return Shell(
      title: 'Mini Statement',
      child: transactions.isEmpty
          ? const Center(
              child: Text(
                'No transactions yet.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 16,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: transactions.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final tx = transactions[index];

                final amount =
                    (tx['amount'] as num?)?.toDouble() ?? 0;

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: mint.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_upward,
                          color: mint,
                        ),
                      ),

                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx['type']?.toString() ??
                                  'Transaction',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tx['date'] == null
                                  ? ''
                                  : formatDate(
                                      tx['date'].toString(),
                                    ),
                              style: const TextStyle(
                                color: Colors.black45,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Text(
                        '-₹${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
