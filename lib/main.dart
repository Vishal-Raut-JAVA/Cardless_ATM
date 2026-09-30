import 'dart:convert';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color ink = Color(0xFF102A43);
const Color mint = Color(0xFF19C7A3);
const Color paper = Color(0xFFF5F8FA);
const Color warn = Color(0xFFB45309);

late SharedPreferences prefs;
late List<CameraDescription> cams;

Map<String, dynamic> db = {};

void seedDb() {
  if (db.isNotEmpty) return;

  Map<String, dynamic> account(String name, String bank, double balance) {
    return {
      'name': name,
      'bank': bank,
      'balance': balance,
      'face': null,
      'fp': false,
      'tx': <Map<String, dynamic>>[],
      'hold': 0.0,
      'pending': null,
    };
  }

  db = {
    '9876500001': account('Aarav Sharma', 'Demo Bank A', 25000.0),
    '9876500002': account('Diya Patil', 'Demo Bank A', 30000.0),
    '9876500003': account('Rohan Mehta', 'Demo Bank B', 35000.0),
    '9876500004': account('Sneha Kulkarni', 'Demo Bank B', 40000.0),
    '9876500005': account('Vikram Singh', 'Demo Bank A', 45000.0),
    '9876500006': account('Ananya Rao', 'Demo Bank B', 50000.0),
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

double asDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

/// Returns the user's pending cardless-withdrawal request, or null if there
/// isn't one. Also returns null (and treats it as gone) if the request is
/// older than 24 hours - callers that need to actually clear an expired
/// request should call [clearIfExpired] first.
Map<String, dynamic>? pendingOf(Map<String, dynamic> user) {
  final raw = user['pending'];
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return null;
}

bool isExpired(Map<String, dynamic> pending) {
  final createdRaw = pending['createdAt'];
  if (createdRaw is! String) return true;
  final created = DateTime.tryParse(createdRaw);
  if (created == null) return true;
  return DateTime.now().difference(created) > const Duration(hours: 24);
}

/// If the user has a pending request that has expired, releases the hold,
/// clears the request, and saves. Returns true if something was cleared.
Future<bool> clearIfExpired(String mobile) async {
  final user = findUser(mobile);
  if (user == null) return false;

  final pending = pendingOf(user);
  if (pending == null) return false;

  if (isExpired(pending)) {
    user['pending'] = null;
    user['hold'] = 0.0;
    db[mobile] = user;
    await saveDb();
    return true;
  }
  return false;
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

  if (yaw.abs() > 35 || roll.abs() > 35) {
    return null;
  }

  final aspectRatio = box.width / box.height;

  final normalizedAspect = aspectRatio.clamp(0.50, 1.20);
  final normalizedYaw = (yaw / 35.0).clamp(-1.0, 1.0);
  final normalizedRoll = (roll / 35.0).clamp(-1.0, 1.0);

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

bool sameFace(List<double> registered, List<double> current) {
  if (registered.isEmpty || current.isEmpty) return false;
  return _difference(registered, current) <= 0.35;
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
  Color? color,
}) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward),
      label: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? mint,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// SMS: sent directly from the device's own SIM via a small native Android
// channel (android/.../MainActivity.kt), wrapping SmsManager. No third-party
// SMS package is used. Requires: a real phone (not an emulator), an active
// SIM with signal, and the user granting the SEND_SMS permission.
// ---------------------------------------------------------------------------

const MethodChannel _smsChannel = MethodChannel('cardless_atm/sms');

class SmsResult {
  final bool sent;
  final String? error;
  const SmsResult(this.sent, this.error);
}

Future<SmsResult> sendOtpSms(String phone, String otp) async {
  try {
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      return const SmsResult(
        false,
        'SMS permission was not granted on this phone.',
      );
    }
  } catch (e) {
    return SmsResult(false, 'Could not request SMS permission: $e');
  }

  try {
    final result = await _smsChannel.invokeMethod<bool>('sendSms', {
      'phone': phone,
      'message':
          'Your Cardless ATM withdrawal OTP is $otp. It is valid for 24 hours. Do not share this OTP with anyone.',
    });

    if (result == true) {
      return const SmsResult(true, null);
    }
    return const SmsResult(
      false,
      'The device did not confirm the SMS was sent.',
    );
  } on PlatformException catch (e) {
    return SmsResult(false, '${e.code}: ${e.message ?? "SMS send failed"}');
  } catch (e) {
    return SmsResult(false, 'Unexpected error sending SMS: $e');
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
        colorScheme: ColorScheme.fromSeed(seedColor: mint),
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
                child: const Icon(Icons.atm, color: Colors.white, size: 42),
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
                style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black54),
              ),
              const Spacer(),
              btn(
                'Get Started',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MobilePage(register: false)),
                  );
                },
                icon: Icons.login,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MobilePage(register: true)),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Register Demo Account', style: TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: ink),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Demo application • No real banking connection',
                  style: TextStyle(fontSize: 12, color: Colors.black45),
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
  const MobilePage({super.key, required this.register});

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

    if (mobile.length != 10 || int.tryParse(mobile) == null) {
      msg(context, 'Enter a valid 10-digit mobile number.');
      return;
    }

    setState(() => loading = true);

    final user = findUser(mobile);

    if (widget.register) {
      final alreadyRegistered =
          user != null && user['face'] != null && user['fp'] == true;

      if (alreadyRegistered) {
        setState(() => loading = false);
        msg(context, 'This number is already registered. Please login.');
        return;
      }

      if (user == null) {
        db[mobile] = {
          'name': 'Demo User',
          'bank': 'Demo Bank',
          'balance': 25000.0,
          'face': null,
          'fp': false,
          'tx': <Map<String, dynamic>>[],
          'hold': 0.0,
          'pending': null,
        };
        await saveDb();
      }

      if (!mounted) return;
      setState(() => loading = false);

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OTPPage(mobile: mobile, register: true)),
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
      msg(context, 'Please register face and fingerprint first.');
      return;
    }

    setState(() => loading = false);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LoginFacePage(mobile: mobile)),
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
              widget.register ? 'Create your demo account' : 'Welcome back',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 10),
            const Text(
              'Enter your registered mobile number to continue.\nUse a REAL number if you want to test the SMS OTP feature.',
              style: TextStyle(color: Colors.black54, fontSize: 15),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 20),
            btn(loading ? 'Please wait...' : 'Continue', loading ? null : continueFlow),
            const SizedBox(height: 20),
            if (!widget.register)
              const Center(
                child: Text(
                  'Demo numbers: 9876500001 to 9876500006',
                  style: TextStyle(color: Colors.black45, fontSize: 12),
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
  const OTPPage({super.key, required this.mobile, required this.register});

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
      MaterialPageRoute(builder: (_) => RegisterFacePage(mobile: widget.mobile)),
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
            const Icon(Icons.sms_outlined, size: 60, color: mint),
            const SizedBox(height: 20),
            const Text('Enter OTP', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)),
            const SizedBox(height: 10),
            Text('OTP sent to ${widget.mobile}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 28),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'OTP',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Demo OTP: 1234', style: TextStyle(color: Colors.black45)),
            const SizedBox(height: 24),
            btn('Verify OTP', verify, icon: Icons.verified),
          ],
        ),
      ),
    );
  }
}

class RegisterFacePage extends StatefulWidget {
  final String mobile;
  const RegisterFacePage({super.key, required this.mobile});

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
          if (mounted) msg(context, 'Account not found.');
          return;
        }
        user['face'] = signature;
        db[widget.mobile] = user;
        await saveDb();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FingerprintPage(mobile: widget.mobile, registration: true),
          ),
        );
      },
    );
  }
}

class LoginFacePage extends StatelessWidget {
  final String mobile;
  const LoginFacePage({super.key, required this.mobile});

  @override
  Widget build(BuildContext context) {
    return FacePage(
      title: 'Face Verification',
      onResult: (signature) async {
        final user = findUser(mobile);
        if (user == null) {
          if (context.mounted) msg(context, 'Account not found.');
          return;
        }

        final storedRaw = user['face'];
        if (storedRaw is! List) {
          if (context.mounted) msg(context, 'Face registration is incomplete.');
          return;
        }

        final stored = storedRaw.map((e) => (e as num).toDouble()).toList();

        if (!sameFace(stored, signature)) {
          if (context.mounted) {
            msg(context, 'Face verification failed. Please look straight and try again.');
          }
          return;
        }

        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FingerprintPage(mobile: mobile, registration: false),
          ),
        );
      },
    );
  }
}

class FacePage extends StatefulWidget {
  final String title;
  final Future<void> Function(List<double> signature) onResult;
  const FacePage({super.key, required this.title, required this.onResult});

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

      final controller = CameraController(selected, ResolutionPreset.medium, enableAudio: false);
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
        hint = 'Camera could not be started: $e';
      });
    }
  }

  Future<void> scanFace() async {
    if (scanning) return;
    final controller = camera;

    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) {
      msg(context, 'Camera is not ready yet.');
      return;
    }

    setState(() {
      scanning = true;
      hint = 'Scanning face...';
    });

    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.10,
      ),
    );

    List<double>? signature;
    String? failureHint;

    try {
      final XFile picture = await controller.takePicture();
      if (picture.path.isEmpty) {
        throw Exception('Camera returned an empty image path.');
      }

      final inputImage = InputImage.fromFilePath(picture.path);
      final faces = await detector.processImage(inputImage);

      if (faces.isEmpty) {
        failureHint = 'No face detected. Move closer and try again.';
      } else if (faces.length > 1) {
        failureHint = 'Only one face should be visible.';
      } else {
        signature = faceSignature(faces.first);
        if (signature == null) {
          failureHint = 'Face is not clear. Look straight and try again.';
        }
      }
    } catch (e, stack) {
      debugPrint('FACE SCAN ERROR: $e');
      debugPrint('$stack');
      failureHint = 'Could not read the face: $e';
    } finally {
      await detector.close();
    }

    if (!mounted) return;

    if (signature == null) {
      setState(() {
        scanning = false;
        hint = failureHint ?? 'Face is not clear. Try again.';
      });
      return;
    }

    setState(() => hint = 'Face detected successfully');

    await widget.onResult(signature);

    if (mounted) setState(() => scanning = false);
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
            const Text('Face verification', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: ink)),
            const SizedBox(height: 8),
            Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 15)),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: loading
                    ? const Center(child: CircularProgressIndicator(color: mint))
                    : controller == null || !controller.value.isInitialized
                        ? const Center(
                            child: Icon(Icons.no_photography_outlined, color: Colors.white54, size: 70),
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
                                    border: Border.all(color: mint, width: 3),
                                  ),
                                ),
                              ),
                              if (scanning)
                                Container(
                                  color: Colors.black26,
                                  child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                                ),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Keep your face inside the frame and look directly at the camera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
            const SizedBox(height: 14),
            btn(scanning ? 'Scanning...' : 'Scan Face', scanning || loading ? null : scanFace, icon: Icons.face),
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
  const FingerprintPage({super.key, required this.mobile, required this.registration});

  @override
  State<FingerprintPage> createState() => _FingerprintPageState();
}

class _FingerprintPageState extends State<FingerprintPage> {
  bool busy = false;

  Future<bool> authenticateFingerprint() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return false;
      if (!await auth.canCheckBiometrics) return false;
      final types = await auth.getAvailableBiometrics();
      if (types.isEmpty) return false;

      return await auth.authenticate(
        localizedReason: widget.registration
            ? 'Verify your fingerprint to complete registration'
            : 'Verify your fingerprint to login',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true, useErrorDialogs: true),
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
      msg(context, 'Fingerprint verification failed or is not available on this device.');
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
        MaterialPageRoute(builder: (_) => RegistrationCompletePage(mobile: widget.mobile)),
        (route) => route.isFirst,
      );
      return;
    }

    if (!mounted) return;
    setState(() => busy = false);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => DashboardPage(mobile: widget.mobile)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: widget.registration ? 'Fingerprint Setup' : 'Fingerprint Verification',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(color: mint.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.fingerprint, size: 90, color: mint),
            ),
            const SizedBox(height: 30),
            Text(
              widget.registration ? 'Register Fingerprint' : 'Verify Fingerprint',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 12),
            Text(
              widget.registration
                  ? 'Use your device fingerprint to complete demo registration.'
                  : 'Use your registered fingerprint to continue.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 36),
            btn(busy ? 'Verifying...' : 'Verify Fingerprint', busy ? null : continueFlow, icon: Icons.fingerprint),
          ],
        ),
      ),
    );
  }
}

class RegistrationCompletePage extends StatelessWidget {
  final String mobile;
  const RegistrationCompletePage({super.key, required this.mobile});

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
              decoration: const BoxDecoration(color: mint, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 60),
            ),
            const SizedBox(height: 28),
            const Text(
              'Registration Complete',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 12),
            Text(
              'Your demo account $mobile is ready.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 15),
            ),
            const SizedBox(height: 32),
            btn(
              'Go to Login',
              () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const MobilePage(register: false)),
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

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

class DashboardPage extends StatefulWidget {
  final String mobile;
  const DashboardPage({super.key, required this.mobile});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? get user => findUser(widget.mobile);
  bool cleaning = true;

  @override
  void initState() {
    super.initState();
    cleanup();
  }

  Future<void> cleanup() async {
    await clearIfExpired(widget.mobile);
    if (mounted) setState(() => cleaning = false);
  }

  String money(dynamic value) => '₹${asDouble(value).toStringAsFixed(2)}';

  void logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cleaning) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: mint)));
    }

    final currentUser = user;
    if (currentUser == null) return const WelcomePage();

    final balance = asDouble(currentUser['balance']);
    final hold = asDouble(currentUser['hold']);
    final available = balance - hold;
    final pending = pendingOf(currentUser);
    final hasPending = pending != null;

    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        title: const Text('Cardless ATM', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: logout, icon: const Icon(Icons.logout))],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await clearIfExpired(widget.mobile);
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Hello, ${currentUser['name']}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 6),
            Text('${currentUser['bank']} • ${widget.mobile}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Account Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                    money(balance),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                  ),
                  if (hold > 0) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.lock_clock, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Text('On hold: ${money(hold)}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Available to withdraw: ${money(available)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (hasPending) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: warn.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: warn.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pending_actions, color: warn),
                        const SizedBox(width: 8),
                        const Text('Pending Cardless Withdrawal', style: TextStyle(fontWeight: FontWeight.w800, color: warn)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Amount: ${money(pending['amount'])}'),
                    const Text('Status: Pending - complete it at the ATM screen.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              btn(
                'Enter ATM OTP',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AtmOtpPage(mobile: widget.mobile)),
                  ).then((_) => setState(() {}));
                },
                icon: Icons.pin,
                color: warn,
              ),
              const SizedBox(height: 12),
            ],

            btn(
              'Cardless Withdrawal',
              hasPending
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CardlessWithdrawPage(mobile: widget.mobile)),
                      ).then((_) => setState(() {}));
                    },
              icon: Icons.payments_outlined,
            ),
            if (hasPending)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Complete or wait for your pending request before raising a new one.',
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => StatementPage(mobile: widget.mobile)),
                );
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text('Mini Statement', style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: ink),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: raise a cardless withdrawal request
// ---------------------------------------------------------------------------

class CardlessWithdrawPage extends StatefulWidget {
  final String mobile;
  const CardlessWithdrawPage({super.key, required this.mobile});

  @override
  State<CardlessWithdrawPage> createState() => _CardlessWithdrawPageState();
}

class _CardlessWithdrawPageState extends State<CardlessWithdrawPage> {
  final amountController = TextEditingController();
  bool sending = false;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  Future<void> raiseRequest() async {
    if (sending) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount < 100 || amount % 100 != 0) {
      msg(context, 'Enter an amount in multiples of ₹100.');
      return;
    }
    if (amount > 20000) {
      msg(context, 'Maximum demo withdrawal is ₹20,000.');
      return;
    }

    final user = findUser(widget.mobile);
    if (user == null) {
      msg(context, 'Account not found.');
      return;
    }

    if (pendingOf(user) != null) {
      msg(context, 'You already have a pending request.');
      return;
    }

    final balance = asDouble(user['balance']);
    final hold = asDouble(user['hold']);
    final available = balance - hold;

    if (amount > available) {
      msg(context, 'Insufficient available balance (₹${available.toStringAsFixed(2)}).');
      return;
    }

    setState(() => sending = true);

    final otp = (100000 + Random().nextInt(900000)).toString();

    user['pending'] = {
      'amount': amount,
      'otp': otp,
      'createdAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    };
    user['hold'] = hold + amount;
    db[widget.mobile] = user;
    await saveDb();

    final smsResult = await sendOtpSms(widget.mobile, otp);

    if (!mounted) return;
    setState(() => sending = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RequestStatusPage(
          mobile: widget.mobile,
          amount: amount,
          smsResult: smsResult,
          otpForFallback: otp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: 'Cardless Withdrawal',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Enter withdrawal amount',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 10),
            const Text(
              'This raises a request. An OTP will be sent to your registered '
              'mobile number by SMS. Money is only deducted after you enter '
              'that OTP at the ATM screen.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 24),
            btn(
              sending ? 'Raising request...' : 'Raise Cardless Withdrawal',
              sending ? null : raiseRequest,
              icon: Icons.send,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: status screen shown right after raising the request
// ---------------------------------------------------------------------------

class RequestStatusPage extends StatelessWidget {
  final String mobile;
  final double amount;
  final SmsResult smsResult;
  final String otpForFallback;

  const RequestStatusPage({
    super.key,
    required this.mobile,
    required this.amount,
    required this.smsResult,
    required this.otpForFallback,
  });

  @override
  Widget build(BuildContext context) {
    return Shell(
      title: 'Request Status',
      back: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: warn.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.pending_actions, color: warn, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Request Raised - Pending',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 10),
            Text('Amount: ₹${amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            Text('Registered number: $mobile', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),

            if (smsResult.sent)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: mint.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: mint),
                    SizedBox(width: 10),
                    Expanded(child: Text('OTP sent by SMS to the registered number.')),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text('SMS could not be sent', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      smsResult.error ?? 'Unknown reason.',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'This can happen without a real SIM/signal (e.g. an emulator), '
                      'or if SMS permission was denied. For this demo only, your OTP is shown below:',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      otpForFallback,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 4, color: ink),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
            const Text(
              'Valid for 24 hours. Go to the ATM screen and enter the OTP to complete the withdrawal.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const Spacer(),
            btn(
              'Go to ATM: Enter OTP',
              () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AtmOtpPage(mobile: mobile)),
                  (route) => route.isFirst,
                );
              },
              icon: Icons.pin,
              color: warn,
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => DashboardPage(mobile: mobile)),
                  (route) => false,
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: ATM screen - enter OTP to actually complete the withdrawal
// ---------------------------------------------------------------------------

class AtmOtpPage extends StatefulWidget {
  final String mobile;
  const AtmOtpPage({super.key, required this.mobile});

  @override
  State<AtmOtpPage> createState() => _AtmOtpPageState();
}

class _AtmOtpPageState extends State<AtmOtpPage> {
  final otpController = TextEditingController();
  bool processing = false;

  @override
  void dispose() {
    otpController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (processing) return;

    final entered = otpController.text.trim();
    if (entered.length != 6) {
      msg(context, 'Enter the 6-digit OTP.');
      return;
    }

    setState(() => processing = true);

    final expired = await clearIfExpired(widget.mobile);
    if (expired) {
      if (!mounted) return;
      setState(() => processing = false);
      msg(context, 'This request has expired. Please raise a new one.');
      Navigator.pop(context);
      return;
    }

    final user = findUser(widget.mobile);
    if (user == null) {
      setState(() => processing = false);
      msg(context, 'Account not found.');
      return;
    }

    final pending = pendingOf(user);
    if (pending == null) {
      setState(() => processing = false);
      msg(context, 'No pending request found.');
      Navigator.pop(context);
      return;
    }

    if (entered != pending['otp']) {
      final attempts = ((pending['attempts'] as num?)?.toInt() ?? 0) + 1;

      if (attempts >= 3) {
        user['pending'] = null;
        user['hold'] = 0.0;
        db[widget.mobile] = user;
        await saveDb();

        if (!mounted) return;
        setState(() => processing = false);
        msg(context, 'Too many wrong attempts. Request cancelled - please raise a new one.');
        Navigator.pop(context);
        return;
      }

      pending['attempts'] = attempts;
      user['pending'] = pending;
      db[widget.mobile] = user;
      await saveDb();

      if (!mounted) return;
      setState(() => processing = false);
      msg(context, 'Incorrect OTP. ${3 - attempts} attempt(s) left.');
      return;
    }

    final amount = asDouble(pending['amount']);
    final balance = asDouble(user['balance']);

    user['balance'] = balance - amount;
    user['hold'] = 0.0;
    user['pending'] = null;

    final transactions = user['tx'];
    final entry = {
      'type': 'Cardless Withdrawal',
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
    };
    if (transactions is List) {
      transactions.insert(0, entry);
    } else {
      user['tx'] = [entry];
    }

    db[widget.mobile] = user;
    await saveDb();

    if (!mounted) return;
    setState(() => processing = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Withdrawal Successful', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          '₹${amount.toStringAsFixed(2)} has been dispensed.\n\nRemaining balance: ₹${(balance - amount).toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => DashboardPage(mobile: widget.mobile)),
                (route) => false,
              );
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
      title: 'ATM: Enter OTP',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.atm, size: 60, color: ink),
            const SizedBox(height: 16),
            const Text(
              'Enter the OTP sent to your registered number',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 10),
            const Text(
              'This step completes the withdrawal. Money is deducted only now.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: 'OTP',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 24),
            btn(
              processing ? 'Verifying...' : 'Confirm & Withdraw',
              processing ? null : submit,
              icon: Icons.check_circle_outline,
              color: warn,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini statement
// ---------------------------------------------------------------------------

class StatementPage extends StatelessWidget {
  final String mobile;
  const StatementPage({super.key, required this.mobile});

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
        child: Center(child: Text('Account not found.')),
      );
    }

    final rawTx = user['tx'];
    final List<Map<String, dynamic>> transactions = [];

    if (rawTx is List) {
      for (final item in rawTx) {
        if (item is Map) {
          transactions.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return Shell(
      title: 'Mini Statement',
      child: transactions.isEmpty
          ? const Center(
              child: Text('No transactions yet.', style: TextStyle(color: Colors.black54, fontSize: 16)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: transactions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final tx = transactions[index];
                final amount = asDouble(tx['amount']);

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: mint.withOpacity(0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_upward, color: mint),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx['type']?.toString() ?? 'Transaction',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: ink),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tx['date'] == null ? '' : formatDate(tx['date'].toString()),
                              style: const TextStyle(color: Colors.black45, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '-₹${amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.redAccent),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
