import 'dart:convert';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ink = Color(0xFF0E2A2B), mint = Color(0xFF2EC4A0), paper = Color(0xFFF4F7F6);
List<CameraDescription> cams = [];
late SharedPreferences prefs;
List<Map<String, dynamic>> db = [];
final fails = <String, int>{};

// ---------- Sample database (dummy data) ----------
List<Map<String, dynamic>> seed() {
  const n = ['Aarav Sharma', 'Diya Patil', 'Rohan Mehta', 'Sneha Kulkarni', 'Vikram Singh', 'Ananya Rao'];
  return [
    for (var i = 0; i < 6; i++)
      <String, dynamic>{
        'mobile': '987650000${i + 1}',
        'name': n[i],
        'bank': i.isEven ? 'Demo Bank A' : 'Demo Bank B',
        'acc': 'XXXX${1000 + i * 111}',
        'balance': 25000 + i * 5000,
        'face': null,
        'fp': false,
        'tx': <String>[],
      }
  ];
}

void save() => prefs.setString('db', jsonEncode(db));

Map<String, dynamic>? find(String m) {
  for (final u in db) {
    if (u['mobile'] == m) return u;
  }
  return null;
}

// ---------- Face helpers ----------
List<double>? signature(Face f) {
  final le = f.landmarks[FaceLandmarkType.leftEye]?.position;
  final re = f.landmarks[FaceLandmarkType.rightEye]?.position;
  final n = f.landmarks[FaceLandmarkType.noseBase]?.position;
  final ml = f.landmarks[FaceLandmarkType.leftMouth]?.position;
  final mr = f.landmarks[FaceLandmarkType.rightMouth]?.position;
  final mb = f.landmarks[FaceLandmarkType.bottomMouth]?.position;
  if (le == null || re == null || n == null || ml == null || mr == null || mb == null) return null;
  if ((f.headEulerAngleY ?? 0).abs() > 15) return null;
  double d(Point<int> a, Point<int> b) => sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  final e = d(le, re);
  if (e == 0) return null;
  return [d(n, le) / e, d(n, re) / e, d(ml, mr) / e, d(n, mb) / e, d(le, ml) / e, d(re, mr) / e];
}

bool sameFace(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - b[i]).abs();
  }
  return s / a.length < 0.12;
}

Future<bool> fingerprint(BuildContext ctx) async {
  final a = LocalAuthentication();
  try {
    if (!await a.isDeviceSupported() || !await a.canCheckBiometrics) {
      if (ctx.mounted) msg(ctx, 'Set up a fingerprint in your phone Settings first.');
      return false;
    }
    return await a.authenticate(
      localizedReason: 'Scan your fingerprint to continue',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
  } catch (_) {
    if (ctx.mounted) msg(ctx, 'Fingerprint scan failed. Try again.');
    return false;
  }
}

// ---------- UI helpers ----------
void msg(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

Widget btn(String t, VoidCallback? f, {bool alt = false}) => SizedBox(
      width: double.infinity,
      height: 52,
      child: alt
          ? OutlinedButton(onPressed: f, child: Text(t))
          : FilledButton(
              onPressed: f,
              style: FilledButton.styleFrom(backgroundColor: mint, foregroundColor: ink),
              child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
    );

class Shell extends StatelessWidget {
  final String title;
  final Widget child;
  final bool back;
  const Shell(this.title, this.child, {super.key, this.back = true});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: paper,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: ink,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: back,
        ),
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: child)),
      );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  try {
    cams = await availableCameras();
  } catch (_) {
    cams = [];
  }
  final s = prefs.getString('db');
  db = s == null ? seed() : (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Cardless ATM',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: mint),
        home: const Welcome(),
      );
}

// ---------- Welcome ----------
class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: ink,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Spacer(),
              const Icon(Icons.face_retouching_natural, color: mint, size: 64),
              const SizedBox(height: 20),
              const Text('Cardless ATM',
                  style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text('Withdraw cash with your face and fingerprint. No card. No PIN.',
                  style: TextStyle(color: Colors.white70, fontSize: 17)),
              const Spacer(),
              btn('Register', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()))),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                  child: const Text('Login'),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ---------- Face capture screen ----------
class FacePage extends StatefulWidget {
  const FacePage({super.key});
  @override
  State<FacePage> createState() => _FaceState();
}

class _FaceState extends State<FacePage> {
  CameraController? c;
  String hint = 'Look straight at the camera';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    if (cams.isEmpty) {
      hint = 'No camera found or permission denied. Allow Camera in Settings.';
      if (mounted) setState(() {});
      return;
    }
    final cam = cams.firstWhere((x) => x.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
    final ctl = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
    try {
      await ctl.initialize();
      c = ctl;
    } catch (_) {
      hint = 'Camera permission denied. Allow Camera in Settings.';
    }
    if (mounted) setState(() {});
  }

  Future<void> shoot() async {
    final ctl = c;
    if (busy || ctl == null || !ctl.value.isInitialized) return;
    setState(() => busy = true);
    final det = FaceDetector(options: FaceDetectorOptions(enableLandmarks: true, performanceMode: FaceDetectorMode.accurate));
    List<double>? result;
    try {
      final f = await ctl.takePicture();
      final faces = await det.processImage(InputImage.fromFilePath(f.path));
      if (faces.isEmpty) {
        hint = 'No face found. Move closer and add light.';
      } else if (faces.length > 1) {
        hint = 'Only one face please.';
      } else {
        result = signature(faces.first);
        if (result == null) hint = 'Face not clear. Look straight at the camera.';
      }
    } catch (_) {
      hint = 'Could not read the face. Try again.';
    }
    await det.close();
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, result);
    } else {
      setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
        'Face scan',
        Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: (c != null && c!.value.isInitialized)
                  ? Center(child: CameraPreview(c!))
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 14),
          Text(hint, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          btn(busy ? 'Scanning...' : 'Scan face', busy ? null : shoot),
        ]),
      );
}

// ---------- Register ----------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegState();
}

class _RegState extends State<RegisterPage> {
  final m = TextEditingController(), o = TextEditingController();
  int step = 0;
  Map<String, dynamic>? u;
  List<double>? face;

  void findAcc() {
    final f = find(m.text.trim());
    if (f == null) return msg(context, 'No account is linked to this number.');
    setState(() {
      u = f;
      step = 1;
    });
  }

  void checkOtp() {
    if (o.text.trim() == '1234') {
      setState(() => step = 2);
    } else {
      msg(context, 'Wrong OTP. Enter 1234 for this demo.');
    }
  }

  Future<void> doFace() async {
    final r = await Navigator.push<List<double>>(context, MaterialPageRoute(builder: (_) => const FacePage()));
    if (r != null) setState(() {
          face = r;
          step = 3;
        });
  }

  Future<void> doFp() async {
    if (await fingerprint(context)) {
      u!['face'] = face;
      u!['fp'] = true;
      save();
      if (mounted) setState(() => step = 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (step) {
      case 0:
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enter your mobile number', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
              controller: m,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: const InputDecoration(labelText: 'Mobile number', border: OutlineInputBorder())),
          const Text('Demo numbers: 9876500001 to 9876500006'),
          const Spacer(),
          btn('Find my account', findAcc),
        ]);
        break;
      case 1:
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
              child: ListTile(
                  leading: const Icon(Icons.account_balance, color: ink),
                  title: Text('${u!['name']}'),
                  subtitle: Text('${u!['bank']}  |  A/C ${u!['acc']}'))),
          const SizedBox(height: 12),
          const Text('Account found. Enter the OTP sent to your number.'),
          const Text('Demo OTP: 1234'),
          const SizedBox(height: 12),
          TextField(
              controller: o,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'OTP', border: OutlineInputBorder())),
          const Spacer(),
          btn('Confirm OTP', checkOtp),
        ]);
        break;
      case 2:
        body = Column(children: [
          const Spacer(),
          const Icon(Icons.face, size: 90, color: ink),
          const Text('Save your face', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const Text('Look straight at the camera in good light.'),
          const Spacer(),
          btn('Open camera', doFace),
        ]);
        break;
      case 3:
        body = Column(children: [
          const Spacer(),
          const Icon(Icons.fingerprint, size: 90, color: ink),
          const Text('Save your fingerprint', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const Text('Touch the fingerprint sensor when asked.'),
          const Spacer(),
          btn('Scan fingerprint', doFp),
        ]);
        break;
      default:
        body = Column(children: [
          const Spacer(),
          const Icon(Icons.check_circle, size: 90, color: mint),
          const Text('Registration complete', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text('${u!['bank']} account linked.'),
          const Spacer(),
          btn('Go to login', () => Navigator.pop(context)),
        ]);
    }
    return Shell('Register', Column(children: [
      LinearProgressIndicator(value: (step + 1) / 5, color: mint),
      const SizedBox(height: 20),
      Expanded(child: body),
    ]));
  }
}

// ---------- Login ----------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final m = TextEditingController();
  int step = 0;
  Map<String, dynamic>? u;

  void findAcc() {
    final mob = m.text.trim();
    if ((fails[mob] ?? 0) >= 3) return msg(context, 'Too many failed tries. Restart the app to try again.');
    final f = find(mob);
    if (f == null) return msg(context, 'No account is linked to this number.');
    if (f['face'] == null || f['fp'] != true) return msg(context, 'This number is not registered yet. Register first.');
    setState(() {
      u = f;
      step = 1;
    });
  }

  void fail(String why) {
    final mob = u!['mobile'] as String;
    fails[mob] = (fails[mob] ?? 0) + 1;
    msg(context, '$why (${fails[mob]}/3 tries used)');
    if (fails[mob]! >= 3) setState(() => step = 0);
  }

  Future<void> doFace() async {
    final r = await Navigator.push<List<double>>(context, MaterialPageRoute(builder: (_) => const FacePage()));
    if (r == null || !mounted) return;
    final saved = (u!['face'] as List).map((e) => (e as num).toDouble()).toList();
    if (sameFace(r, saved)) {
      setState(() => step = 2);
    } else {
      fail('Face did not match');
    }
  }

  Future<void> doFp() async {
    if (await fingerprint(context)) {
      if (!mounted) return;
      fails.remove(u!['mobile']);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Dashboard(u!)));
    } else if (mounted) {
      fail('Fingerprint not accepted');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (step == 0) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Enter your mobile number', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
            controller: m,
            keyboardType: TextInputType.number,
            maxLength: 10,
            decoration: const InputDecoration(labelText: 'Mobile number', border: OutlineInputBorder())),
        const Spacer(),
        btn('Continue', findAcc),
      ]);
    } else if (step == 1) {
      body = Column(children: [
        const Spacer(),
        const Icon(Icons.face, size: 90, color: ink),
        Text('Hello, ${u!['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const Text('Step 1 of 2: scan your face'),
        const Spacer(),
        btn('Open camera', doFace),
      ]);
    } else {
      body = Column(children: [
        const Spacer(),
        const Icon(Icons.fingerprint, size: 90, color: ink),
        const Text('Step 2 of 2: scan your fingerprint', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Spacer(),
        btn('Scan fingerprint', doFp),
      ]);
    }
    return Shell('Login', body);
  }
}

// ---------- Dashboard ----------
class Dashboard extends StatefulWidget {
  final Map<String, dynamic> u;
  const Dashboard(this.u, {super.key});
  @override
  State<Dashboard> createState() => _DashState();
}

class _DashState extends State<Dashboard> {
  void info(String title, String body) => showDialog(
      context: context,
      builder: (_) => AlertDialog(
          title: Text(title), content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final tx = (u['tx'] as List).take(5).join('\n');
    return Shell(
      'Cardless ATM',
      back: false,
      Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${u['name']}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            Text('${u['bank']}  |  A/C ${u['acc']}', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 24),
        btn('Withdraw cash', () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => WithdrawPage(u)));
          setState(() {});
        }),
        const SizedBox(height: 12),
        btn('Check balance', () => info('Balance', '₹${u['balance']}'), alt: true),
        const SizedBox(height: 12),
        btn('Mini statement', () => info('Last transactions', tx.isEmpty ? 'No transactions yet.' : tx), alt: true),
        const Spacer(),
        btn('Logout', () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Welcome()), (_) => false),
            alt: true),
      ]),
    );
  }
}

// ---------- Withdraw ----------
class WithdrawPage extends StatefulWidget {
  final Map<String, dynamic> u;
  const WithdrawPage(this.u, {super.key});
  @override
  State<WithdrawPage> createState() => _WdState();
}

class _WdState extends State<WithdrawPage> {
  final a = TextEditingController();

  void go() {
    final amt = int.tryParse(a.text.trim()) ?? 0;
    final u = widget.u;
    if (amt < 100 || amt % 100 != 0) return msg(context, 'Enter an amount in multiples of ₹100.');
    if (amt > 20000) return msg(context, 'Daily limit is ₹20,000.');
    if (amt > (u['balance'] as int)) return msg(context, 'Not enough balance.');
    u['balance'] = (u['balance'] as int) - amt;
    (u['tx'] as List).insert(0, 'Withdrawn ₹$amt');
    save();
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
              title: const Text('Success'),
              content: Text('Collect your ₹$amt.\nNew balance: ₹${u['balance']}'),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    child: const Text('Done'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => Shell(
        'Withdraw cash',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            for (final v in [500, 1000, 2000, 5000]) ActionChip(label: Text('₹$v'), onPressed: () => setState(() => a.text = '$v')),
          ]),
          const SizedBox(height: 16),
          TextField(
              controller: a,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount in ₹', border: OutlineInputBorder())),
          const Spacer(),
          btn('Withdraw', go),
        ]),
      );
}
