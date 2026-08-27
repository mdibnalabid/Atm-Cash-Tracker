import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// ─────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────

enum CashStatus { available, low, empty }

enum QueueLength { noLine, shortLine, longLine }

extension CashStatusX on CashStatus {
  String get label {
    switch (this) {
      case CashStatus.available:
        return 'Cash Available';
      case CashStatus.low:
        return 'Cash Low';
      case CashStatus.empty:
        return 'No Cash';
    }
  }

  Color get color {
    switch (this) {
      case CashStatus.available:
        return const Color(0xFF2E7D32);
      case CashStatus.low:
        return const Color(0xFFE65100);
      case CashStatus.empty:
        return const Color(0xFFC62828);
    }
  }

  Color get lightColor {
    switch (this) {
      case CashStatus.available:
        return const Color(0xFFE8F5E9);
      case CashStatus.low:
        return const Color(0xFFFFF3E0);
      case CashStatus.empty:
        return const Color(0xFFFFEBEE);
    }
  }

  IconData get icon {
    switch (this) {
      case CashStatus.available:
        return Icons.check_circle;
      case CashStatus.low:
        return Icons.warning_amber;
      case CashStatus.empty:
        return Icons.cancel;
    }
  }
}

extension QueueLengthX on QueueLength {
  String get label {
    switch (this) {
      case QueueLength.noLine:
        return 'No queue';
      case QueueLength.shortLine:
        return 'Short queue';
      case QueueLength.longLine:
        return 'Long queue';
    }
  }

  IconData get icon {
    switch (this) {
      case QueueLength.noLine:
        return Icons.person_outline;
      case QueueLength.shortLine:
        return Icons.people_outline;
      case QueueLength.longLine:
        return Icons.people;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────

class AtmInfo {
  final String id;
  final String bankName;
  final String address;
  final double fallbackDistance;
  final CashStatus status;
  final Timestamp lastUpdated;
  final QueueLength queueLength;
  final String notes;
  final double latitude;
  final double longitude;

  const AtmInfo({
    required this.id,
    required this.bankName,
    required this.address,
    required this.fallbackDistance,
    required this.status,
    required this.lastUpdated,
    required this.queueLength,
    required this.notes,
    required this.latitude,
    required this.longitude,
  });

  factory AtmInfo.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AtmInfo(
      id: doc.id,
      bankName: d['bankName'] ?? '',
      address: d['address'] ?? '',
      fallbackDistance: (d['fallbackDistance'] ?? 0).toDouble(),
      status: CashStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'empty'),
        orElse: () => CashStatus.empty,
      ),
      lastUpdated: d['lastUpdated'] ?? Timestamp.now(),
      queueLength: QueueLength.values.firstWhere(
        (e) => e.name == (d['queueLength'] ?? 'noLine'),
        orElse: () => QueueLength.noLine,
      ),
      notes: d['notes'] ?? '',
      latitude: (d['latitude'] ?? 0).toDouble(),
      longitude: (d['longitude'] ?? 0).toDouble(),
    );
  }
}

class AtmReport {
  final String id;
  final String userId;
  final String displayName;
  final String? photoUrl;
  final CashStatus status;
  final QueueLength queueLength;
  final String notes;
  final Timestamp timestamp;

  const AtmReport({
    required this.id,
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.status,
    required this.queueLength,
    required this.notes,
    required this.timestamp,
  });

  factory AtmReport.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AtmReport(
      id: doc.id,
      userId: d['userId'] ?? '',
      displayName: d['displayName'] ?? 'Anonymous',
      photoUrl: d['photoUrl'],
      status: CashStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'empty'),
        orElse: () => CashStatus.empty,
      ),
      queueLength: QueueLength.values.firstWhere(
        (e) => e.name == (d['queueLength'] ?? 'noLine'),
        orElse: () => QueueLength.noLine,
      ),
      notes: d['notes'] ?? '',
      timestamp: d['timestamp'] ?? Timestamp.now(),
    );
  }

  String get timeAgo {
    final now = DateTime.now();
    final then = timestamp.toDate();
    final diff = now.difference(then);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(then);
  }
}

// ─────────────────────────────────────────────────────────────
// AUTH SERVICE
// ─────────────────────────────────────────────────────────────

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get userStream => _auth.authStateChanges();

  /// Returns `(credential, null)` on success or `(null, errorMessage)` on failure.
  /// The caller is responsible for surfacing the error to the user.
  Future<(UserCredential?, String?)> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // On web, Firebase Auth owns the full OAuth popup — do NOT go through
        // the google_sign_in package, which opens its own popup and causes an
        // immediate close because the two flows conflict with each other.
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final credential = await _auth.signInWithPopup(provider);
        return (credential, null);
      } else {
        // On Android/iOS, use the native Google Sign-In flow to get tokens,
        // then hand them to Firebase Auth.
        // Imported inline to keep the web path free of the package dependency.
        // ignore: undefined_identifier
        final googleSignIn = _NativeGoogleSignIn._instance;
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          // User cancelled — not an error worth showing.
          return (null, null);
        }
        final googleAuth = await googleUser.authentication;
        final oauthCredential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final credential = await _auth.signInWithCredential(oauthCredential);
        return (credential, null);
      }
    } on FirebaseAuthException catch (e) {
      final msg = _friendlyAuthError(e);
      debugPrint('FirebaseAuthException [${e.code}]: ${e.message}');
      return (null, msg);
    } catch (e) {
      debugPrint('Google Sign-In unexpected error: $e');
      return (null, 'Sign-in failed. Please try again.');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    // Native sign-out is best-effort; ignore errors.
    if (!kIsWeb) {
      try {
        await _NativeGoogleSignIn._instance.signOut();
      } catch (_) {}
    }
  }

  static String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
        return 'Sign-in cancelled — the popup was closed before completing.';
      case 'popup-blocked':
        return 'Popup blocked by browser. Allow popups for this site and try again.';
      case 'cancelled-popup-request':
        // Fired when a second popup is opened before the first resolves — harmless.
        return '';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}). Please try again.';
    }
  }
}

// Thin wrapper so the Android/iOS google_sign_in call is isolated from the
// web code path. On web this class is never instantiated.
class _NativeGoogleSignIn {
  static final _NativeGoogleSignIn _instance = _NativeGoogleSignIn._();
  _NativeGoogleSignIn._();

  // Lazy so we don't touch the package on web at all.
  // ignore: undefined_identifier
  final _impl = GoogleSignIn(scopes: ['email', 'profile']);

  // ignore: undefined_identifier
  Future<GoogleSignInAccount?> signIn() => _impl.signIn();
  Future<void> signOut() => _impl.signOut();
}

// ─────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'atm_booths';
  static const Duration _spamWindow = Duration(hours: 1);

  Stream<List<AtmInfo>> streamAtms() {
    return _db
        .collection(_collection)
        .snapshots()
        .map((snap) => snap.docs.map(AtmInfo.fromFirestore).toList());
  }

  Stream<List<AtmReport>> streamReports(String atmId, {int limit = 10}) {
    return _db
        .collection(_collection)
        .doc(atmId)
        .collection('reports')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(AtmReport.fromFirestore).toList());
  }

  /// Returns null on success, or an error string.
  Future<String?> updateAtmStatus({
    required String atmId,
    required CashStatus status,
    required QueueLength queueLength,
    required String notes,
    required User user,
  }) async {
    // Spam check — one report per user per ATM per hour
    final spamCheck = await _checkSpam(atmId: atmId, userId: user.uid);
    if (spamCheck != null) return spamCheck;

    final batch = _db.batch();
    final atmRef = _db.collection(_collection).doc(atmId);
    final reportRef = atmRef.collection('reports').doc();

    final reportData = {
      'userId': user.uid,
      'displayName': user.displayName ?? 'Anonymous',
      'photoUrl': user.photoURL,
      'status': status.name,
      'queueLength': queueLength.name,
      'notes': notes.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    batch.update(atmRef, {
      'status': status.name,
      'queueLength': queueLength.name,
      'notes': notes.trim(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastReportedBy': user.displayName ?? 'Anonymous',
    });

    batch.set(reportRef, reportData);
    await batch.commit();
    return null;
  }

  Future<String?> _checkSpam({
    required String atmId,
    required String userId,
  }) async {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(_spamWindow));
    final snap = await _db
        .collection(_collection)
        .doc(atmId)
        .collection('reports')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThan: cutoff)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      final lastReport = snap.docs.first.data();
      final lastTs = lastReport['timestamp'] as Timestamp?;
      if (lastTs != null) {
        final diff = DateTime.now().difference(lastTs.toDate());
        final remaining = _spamWindow - diff;
        final mins = remaining.inMinutes + 1;
        return 'You already reported this ATM. Please wait $mins more minute${mins == 1 ? '' : 's'}.';
      }
      return 'You already reported this ATM recently. Please wait before reporting again.';
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────
// MARKER HELPER
// ─────────────────────────────────────────────────────────────

Future<BitmapDescriptor> _buildMarker(CashStatus status) async {
  final color = status.color;
  const size = 48.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.25)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  canvas.drawCircle(
    const Offset(size / 2, size / 2 + 2),
    size / 2 - 4,
    shadowPaint,
  );

  final bgPaint = Paint()..color = Colors.white;
  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 4, bgPaint);

  final fillPaint = Paint()..color = color;
  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 8, fillPaint);

  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
}

Future<BitmapDescriptor> _buildUserMarker() async {
  const size = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.3)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  canvas.drawCircle(
    const Offset(size / 2, size / 2 + 3),
    size / 2 - 6,
    shadowPaint,
  );

  final ringPaint = Paint()..color = Colors.white;
  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 4, ringPaint);

  final corePaint = Paint()..color = const Color(0xFF1565C0);
  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 12, corePaint);

  final dotPaint = Paint()..color = Colors.white;
  canvas.drawCircle(const Offset(size / 2, size / 2), 8, dotPaint);

  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
}

// ─────────────────────────────────────────────────────────────
// DISTANCE HELPER
// ─────────────────────────────────────────────────────────────

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _deg2rad(double deg) => deg * pi / 180;

String _fmtDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

// ─────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AtmTrackerApp());
}

// Global key so AuthService errors can show snackbars even after a dialog
// has been popped and its BuildContext is no longer valid.
final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void _showAuthErrorSnackbar(String message) {
  if (message.isEmpty) return; // cancelled-popup-request — nothing to show
  _scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
}

class AtmTrackerApp extends StatelessWidget {
  const AtmTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'ATM Cash Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _fs = FirestoreService();
  final AuthService _auth = AuthService();

  List<AtmInfo> _allAtms = [];
  List<AtmInfo> _filtered = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<List<AtmInfo>>? _atmSub;

  // View
  bool _isMapView = false;

  // Filters
  String _searchQuery = '';
  final Set<CashStatus> _statusFilters = {};
  final Set<String> _bankFilters = {};

  // Location
  Position? _userPosition;
  bool _locationLoading = false;

  // Map
  GoogleMapController? _mapController;
  Map<MarkerId, Marker> _markers = {};
  BitmapDescriptor? _markerAvailable;
  BitmapDescriptor? _markerLow;
  BitmapDescriptor? _markerEmpty;
  BitmapDescriptor? _userMarker;
  Marker? _userPosMarker;

  // Auth
  User? _currentUser;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _initMarkers();
    _subscribeAtms();
    _initLocation();
    _authSub = _auth.userStream.listen((user) {
      if (mounted) setState(() => _currentUser = user);
    });
  }

  @override
  void dispose() {
    _atmSub?.cancel();
    _authSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initMarkers() async {
    _markerAvailable = await _buildMarker(CashStatus.available);
    _markerLow = await _buildMarker(CashStatus.low);
    _markerEmpty = await _buildMarker(CashStatus.empty);
    _userMarker = await _buildUserMarker();
  }

  void _subscribeAtms() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _atmSub?.cancel();
    _atmSub = _fs.streamAtms().listen(
      (atms) {
        if (!mounted) return;
        setState(() {
          _allAtms = atms;
          _loading = false;
          _error = null;
        });
        _applyFilters();
        _rebuildMarkers();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      },
    );
  }

  Future<void> _initLocation() async {
    setState(() => _locationLoading = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() => _locationLoading = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _locationLoading = false;
      });
      _applyFilters();
      _updateUserMarker(pos);
    } catch (_) {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  void _updateUserMarker(Position pos) {
    if (_userMarker == null) return;
    final marker = Marker(
      markerId: const MarkerId('__user__'),
      position: LatLng(pos.latitude, pos.longitude),
      icon: _userMarker!,
      zIndex: 10,
      infoWindow: const InfoWindow(title: 'You are here'),
    );
    setState(() {
      _userPosMarker = marker;
      _markers['__user__' as MarkerId] = marker;
    });
    final all = {..._markers};
    all[const MarkerId('__user__')] = marker;
    setState(() => _markers = all);
  }

  void _applyFilters() {
    var list = List<AtmInfo>.from(_allAtms);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where(
            (a) =>
                a.bankName.toLowerCase().contains(q) ||
                a.address.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_statusFilters.isNotEmpty) {
      list = list.where((a) => _statusFilters.contains(a.status)).toList();
    }
    if (_bankFilters.isNotEmpty) {
      list = list.where((a) => _bankFilters.contains(a.bankName)).toList();
    }
    if (_userPosition != null) {
      list.sort((a, b) {
        final dA = _haversine(
          _userPosition!.latitude,
          _userPosition!.longitude,
          a.latitude,
          a.longitude,
        );
        final dB = _haversine(
          _userPosition!.latitude,
          _userPosition!.longitude,
          b.latitude,
          b.longitude,
        );
        return dA.compareTo(dB);
      });
    }
    setState(() => _filtered = list);
  }

  void _rebuildMarkers() {
    final newMarkers = <MarkerId, Marker>{};
    if (_userPosMarker != null) {
      newMarkers[const MarkerId('__user__')] = _userPosMarker!;
    }
    for (final atm in _allAtms) {
      final mid = MarkerId(atm.id);
      newMarkers[mid] = Marker(
        markerId: mid,
        position: LatLng(atm.latitude, atm.longitude),
        icon: _iconFor(atm.status),
        onTap: () => _showDetail(atm),
        infoWindow: InfoWindow(title: atm.bankName, snippet: atm.address),
      );
    }
    setState(() => _markers = newMarkers);
  }

  BitmapDescriptor _iconFor(CashStatus s) {
    switch (s) {
      case CashStatus.available:
        return _markerAvailable ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      case CashStatus.low:
        return _markerLow ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case CashStatus.empty:
        return _markerEmpty ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
  }

  void _showDetail(AtmInfo atm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AtmDetailSheet(
        atm: atm,
        userPosition: _userPosition,
        currentUser: _currentUser,
        onReportTap: () {
          Navigator.pop(context);
          _openReportScreen(atm);
        },
      ),
    );
  }

  void _openReportScreen(AtmInfo atm) {
    if (_currentUser == null) {
      _promptSignIn(onSuccess: () => _openReportScreen(atm));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportScreen(atm: atm, user: _currentUser!),
      ),
    );
  }

  void _promptSignIn({VoidCallback? onSuccess}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign in required'),
        content: const Text(
          'Sign in with Google to report ATM status. Your name will appear in the report history so others can trust the information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              // Dialog context is gone after pop — use the global key for snackbars.
              final (credential, error) = await _auth.signInWithGoogle();
              if (error != null) {
                _showAuthErrorSnackbar(error);
                return;
              }
              if (credential != null && mounted) {
                setState(() => _currentUser = credential.user);
                onSuccess?.call();
              }
            },
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        ],
      ),
    );
  }

  void _findNearestWithCash() {
    if (_userPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available yet')),
      );
      return;
    }
    final candidates = _allAtms
        .where((a) => a.status == CashStatus.available)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No ATMs with cash found')));
      return;
    }
    candidates.sort((a, b) {
      final dA = _haversine(
        _userPosition!.latitude,
        _userPosition!.longitude,
        a.latitude,
        a.longitude,
      );
      final dB = _haversine(
        _userPosition!.latitude,
        _userPosition!.longitude,
        b.latitude,
        b.longitude,
      );
      return dA.compareTo(dB);
    });
    final nearest = candidates.first;
    final dist = _haversine(
      _userPosition!.latitude,
      _userPosition!.longitude,
      nearest.latitude,
      nearest.longitude,
    );

    setState(() => _isMapView = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(nearest.latitude, nearest.longitude),
          16,
        ),
      );
      Future.delayed(
        const Duration(milliseconds: 600),
        () => _showDetail(nearest),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2E7D32),
        content: Text(
          '${nearest.bankName} — ${_fmtDistance(dist)} away',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  void _centerOnUser() {
    if (_userPosition == null) return;
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
      ),
    );
  }

  void _fitAllMarkers() {
    if (_allAtms.isEmpty) return;
    double minLat = _allAtms.first.latitude;
    double maxLat = _allAtms.first.latitude;
    double minLng = _allAtms.first.longitude;
    double maxLng = _allAtms.first.longitude;
    for (final a in _allAtms) {
      minLat = min(minLat, a.latitude);
      maxLat = max(maxLat, a.latitude);
      minLng = min(minLng, a.longitude);
      maxLng = max(maxLng, a.longitude);
    }
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.005, minLng - 0.005),
          northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
        ),
        60,
      ),
    );
  }

  void _showFilterSheet() {
    final banks = _allAtms.map((a) => a.bankName).toSet().toList()..sort();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        banks: banks,
        activeStatus: Set.from(_statusFilters),
        activeBanks: Set.from(_bankFilters),
        onApply: (status, banks) {
          setState(() {
            _statusFilters
              ..clear()
              ..addAll(status);
            _bankFilters
              ..clear()
              ..addAll(banks);
          });
          _applyFilters();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = _statusFilters.isNotEmpty || _bankFilters.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ATM Cash Tracker',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Auth widget
          StreamBuilder<User?>(
            stream: _auth.userStream,
            builder: (context, snapshot) {
              final user = snapshot.data;
              if (user == null) {
                return TextButton.icon(
                  onPressed: () async {
                    final (credential, error) = await _auth.signInWithGoogle();
                    if (error != null) {
                      _showAuthErrorSnackbar(error);
                      return;
                    }
                    if (credential != null && mounted) {
                      setState(() => _currentUser = credential.user);
                    }
                  },
                  icon: const Icon(Icons.login, color: Colors.white),
                  label: const Text(
                    'Sign in',
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PopupMenuButton<String>(
                  offset: const Offset(0, 48),
                  child: Row(
                    children: [
                      _UserAvatar(
                        photoUrl: user.photoURL,
                        radius: 16,
                        backgroundColor: Colors.white24,
                        iconColor: Colors.white,
                        iconSize: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user.displayName?.split(' ').first ?? 'Me',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            user.email ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'signout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 8),
                          Text('Sign out'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'signout') _auth.signOut();
                  },
                ),
              );
            },
          ),
          // View toggle
          IconButton(
            icon: Icon(_isMapView ? Icons.list : Icons.map),
            tooltip: _isMapView ? 'List view' : 'Map view',
            onPressed: () => setState(() => _isMapView = !_isMapView),
          ),
          // Filter button
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Filter',
                onPressed: _showFilterSheet,
              ),
              if (hasFilters)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _subscribeAtms, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildSearchBar(),
        if (_userPosition != null && !_isMapView)
          Container(
            color: const Color(0xFFE3F2FD),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.near_me, size: 14, color: Color(0xFF1565C0)),
                const SizedBox(width: 6),
                const Text(
                  'Sorted by distance from you',
                  style: TextStyle(fontSize: 12, color: Color(0xFF1565C0)),
                ),
              ],
            ),
          ),
        Expanded(child: _isMapView ? _buildMapView() : _buildListView()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search bank or address…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() => _searchQuery = '');
                    _applyFilters();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
        onChanged: (v) {
          setState(() => _searchQuery = v);
          _applyFilters();
        },
      ),
    );
  }

  Widget _buildListView() {
    if (_filtered.isEmpty) {
      return const Center(
        child: Text(
          'No ATMs match your filters.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _AtmListTile(
        atm: _filtered[i],
        userPosition: _userPosition,
        onTap: () => _showDetail(_filtered[i]),
      ),
    );
  }

  Widget _buildMapView() {
    const initialDhaka = LatLng(23.8103, 90.4125);
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: initialDhaka,
            zoom: 13,
          ),
          markers: _markers.values.toSet(),
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (ctrl) => _mapController = ctrl,
        ),
        // ATM count badge
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Text(
              '${_allAtms.length} ATMs',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        // Legend
        Positioned(
          bottom: 100,
          left: 12,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: CashStatus.values
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(s.label, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        // Map FABs
        Positioned(
          right: 12,
          bottom: 100,
          child: Column(
            children: [
              _MapFab(
                icon: Icons.my_location,
                tooltip: 'Center on me',
                onTap: _centerOnUser,
              ),
              const SizedBox(height: 8),
              _MapFab(
                icon: Icons.fit_screen,
                tooltip: 'Fit all markers',
                onTap: _fitAllMarkers,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _buildFab() {
    if (_isMapView) return null;
    return FloatingActionButton.extended(
      onPressed: _findNearestWithCash,
      backgroundColor: const Color(0xFF2E7D32),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.atm),
      label: const Text('Nearest with Cash'),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MAP FAB
// ─────────────────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapFab({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: const Color(0xFF1565C0)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ATM LIST TILE
// ─────────────────────────────────────────────────────────────

class _AtmListTile extends StatelessWidget {
  final AtmInfo atm;
  final Position? userPosition;
  final VoidCallback onTap;

  const _AtmListTile({
    required this.atm,
    required this.userPosition,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final distStr = userPosition != null
        ? _fmtDistance(
            _haversine(
              userPosition!.latitude,
              userPosition!.longitude,
              atm.latitude,
              atm.longitude,
            ),
          )
        : '~${_fmtDistance(atm.fallbackDistance * 1000)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: atm.status.lightColor,
          child: Icon(atm.status.icon, color: atm.status.color),
        ),
        title: Text(
          atm.bankName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          atm.address,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: atm.status.lightColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                atm.status.label,
                style: TextStyle(
                  color: atm.status.color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              distStr,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FILTER SHEET
// ─────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final List<String> banks;
  final Set<CashStatus> activeStatus;
  final Set<String> activeBanks;
  final void Function(Set<CashStatus>, Set<String>) onApply;

  const _FilterSheet({
    required this.banks,
    required this.activeStatus,
    required this.activeBanks,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<CashStatus> _status;
  late Set<String> _banks;

  @override
  void initState() {
    super.initState();
    _status = Set.from(widget.activeStatus);
    _banks = Set.from(widget.activeBanks);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Filters',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _status.clear();
                    _banks.clear();
                  });
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Cash status',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: CashStatus.values
                .map(
                  (s) => FilterChip(
                    label: Text(s.label),
                    selected: _status.contains(s),
                    selectedColor: s.lightColor,
                    checkmarkColor: s.color,
                    labelStyle: TextStyle(
                      color: _status.contains(s) ? s.color : null,
                    ),
                    onSelected: (v) =>
                        setState(() => v ? _status.add(s) : _status.remove(s)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Bank',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: widget.banks
                .map(
                  (b) => FilterChip(
                    label: Text(b),
                    selected: _banks.contains(b),
                    onSelected: (v) =>
                        setState(() => v ? _banks.add(b) : _banks.remove(b)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onApply(_status, _banks);
              },
              child: const Text('Apply filters'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ATM DETAIL SHEET
// ─────────────────────────────────────────────────────────────

class AtmDetailSheet extends StatelessWidget {
  final AtmInfo atm;
  final Position? userPosition;
  final User? currentUser;
  final VoidCallback onReportTap;

  const AtmDetailSheet({
    super.key,
    required this.atm,
    required this.userPosition,
    required this.currentUser,
    required this.onReportTap,
  });

  @override
  Widget build(BuildContext context) {
    final distStr = userPosition != null
        ? _fmtDistance(
            _haversine(
              userPosition!.latitude,
              userPosition!.longitude,
              atm.latitude,
              atm.longitude,
            ),
          )
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: atm.status.lightColor,
                  radius: 24,
                  child: Icon(
                    atm.status.icon,
                    color: atm.status.color,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        atm.bankName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        atm.address,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (distStr != null)
                        Text(
                          '$distStr away',
                          style: const TextStyle(
                            color: Color(0xFF1565C0),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Status card
            _InfoCard(
              color: atm.status.lightColor,
              child: Row(
                children: [
                  Icon(atm.status.icon, color: atm.status.color),
                  const SizedBox(width: 10),
                  Text(
                    atm.status.label,
                    style: TextStyle(
                      color: atm.status.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _timeAgo(atm.lastUpdated),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Queue card
            _InfoCard(
              child: Row(
                children: [
                  Icon(atm.queueLength.icon, color: Colors.grey.shade700),
                  const SizedBox(width: 10),
                  Text(atm.queueLength.label),
                ],
              ),
            ),
            if (atm.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        atm.notes,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _launchDirections(context, atm),
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Directions'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onReportTap,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Report'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Report history section
            const Text(
              'Recent Reports',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _ReportHistoryTimeline(atmId: atm.id),
          ],
        ),
      ),
    );
  }

  void _launchDirections(BuildContext context, AtmInfo atm) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${atm.latitude},${atm.longitude}&travelmode=walking',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _timeAgo(Timestamp ts) {
    final now = DateTime.now();
    final then = ts.toDate();
    final diff = now.difference(then);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(then);
  }
}

// ─────────────────────────────────────────────────────────────
// REPORT HISTORY TIMELINE
// ─────────────────────────────────────────────────────────────

class _ReportHistoryTimeline extends StatelessWidget {
  final String atmId;

  const _ReportHistoryTimeline({required this.atmId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AtmReport>>(
      stream: FirestoreService().streamReports(atmId, limit: 8),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final reports = snap.data ?? [];
        if (reports.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Column(
              children: [
                Icon(Icons.history, color: Colors.grey, size: 32),
                SizedBox(height: 8),
                Text(
                  'No reports yet.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                Text(
                  'Be the first to report this ATM!',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            for (int i = 0; i < reports.length; i++)
              _ReportTimelineItem(
                report: reports[i],
                isLast: i == reports.length - 1,
              ),
          ],
        );
      },
    );
  }
}

class _ReportTimelineItem extends StatelessWidget {
  final AtmReport report;
  final bool isLast;

  const _ReportTimelineItem({required this.report, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: report.status.lightColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: report.status.color, width: 1.5),
                  ),
                  child: Icon(
                    report.status.icon,
                    color: report.status.color,
                    size: 14,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Colors.grey.shade200),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Avatar
                      _UserAvatar(
                        photoUrl: report.photoUrl,
                        radius: 10,
                        iconSize: 12,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          report.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        report.timeAgo,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Status badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: report.status.lightColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          report.status.label,
                          style: TextStyle(
                            color: report.status.color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· ${report.queueLength.label}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (report.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      report.notes,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// USER AVATAR HELPER
// ─────────────────────────────────────────────────────────────

/// Renders a circular avatar from a network URL with a guaranteed fallback.
/// Uses [Image.network] + [errorBuilder] instead of [CircleAvatar.backgroundImage]
/// because [backgroundImage] has no error hook — a 429 or any HTTP error silently
/// leaves the widget in a broken paint state and can propagate exceptions that
/// freeze the loading spinner in parent screens.
class _UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  final Color backgroundColor;
  final Color iconColor;
  final double? iconSize;

  const _UserAvatar({
    required this.photoUrl,
    required this.radius,
    this.backgroundColor = const Color(0xFF1565C0),
    this.iconColor = Colors.white,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Icon(Icons.person, size: iconSize ?? radius, color: iconColor),
    );

    if (photoUrl == null || photoUrl!.isEmpty) return fallback;

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: Image.network(
          photoUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          // Any HTTP error (429 rate-limit, 403, network failure) renders the
          // fallback icon instead of throwing and breaking the parent widget.
          errorBuilder: (_, _, _) =>
              Icon(Icons.person, size: iconSize ?? radius, color: iconColor),
          // Show the fallback while loading too, so there's no blank flash.
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Icon(
              Icons.person,
              size: iconSize ?? radius,
              color: iconColor,
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INFO CARD HELPER
// ─────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final Widget child;
  final Color? color;

  const _InfoCard({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REPORT SCREEN
// ─────────────────────────────────────────────────────────────

class ReportScreen extends StatefulWidget {
  final AtmInfo atm;
  final User user;

  const ReportScreen({super.key, required this.atm, required this.user});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final FirestoreService _fs = FirestoreService();
  final _notesController = TextEditingController();

  CashStatus _selectedStatus = CashStatus.available;
  QueueLength _selectedQueue = QueueLength.noLine;
  bool _loading = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    String? error;
    bool success = false;
    try {
      error = await _fs.updateAtmStatus(
        atmId: widget.atm.id,
        status: _selectedStatus,
        queueLength: _selectedQueue,
        notes: _notesController.text,
        user: widget.user,
      );
      if (error == null) success = true;
    } catch (e) {
      error = 'Submission failed. Please check your connection and try again.';
      debugPrint('_submit unexpected error: $e');
    } finally {
      // Always stop the spinner — even if a network image error or any other
      // exception propagated up through updateAtmStatus.
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade700,
          content: Row(
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(error, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2E7D32),
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Report submitted — thank you!',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report ATM Status')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ATM header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.atm.bankName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.atm.address,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Reporting as — user identity chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: Row(
              children: [
                _UserAvatar(
                  photoUrl: widget.user.photoURL,
                  radius: 14,
                  iconSize: 16,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reporting as',
                      style: TextStyle(fontSize: 11, color: Color(0xFF1565C0)),
                    ),
                    Text(
                      widget.user.displayName ?? widget.user.email ?? 'You',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Icon(
                  Icons.verified_user,
                  color: Color(0xFF1565C0),
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Cash status',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ...CashStatus.values.map(
            (s) => RadioListTile<CashStatus>(
              value: s,
              groupValue: _selectedStatus,
              onChanged: (v) => setState(() => _selectedStatus = v!),
              title: Row(
                children: [
                  Icon(s.icon, color: s.color, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    s.label,
                    style: TextStyle(
                      color: s.color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              activeColor: s.color,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Queue length',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ...QueueLength.values.map(
            (q) => RadioListTile<QueueLength>(
              value: q,
              groupValue: _selectedQueue,
              onChanged: (v) => setState(() => _selectedQueue = v!),
              title: Row(
                children: [
                  Icon(q.icon, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text(q.label),
                ],
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _notesController,
            maxLength: 120,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. Machine on the left is broken',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Submit Report', style: TextStyle(fontSize: 16)),
            ),
          ),

          // Spam notice
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                'One report per ATM per hour.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
