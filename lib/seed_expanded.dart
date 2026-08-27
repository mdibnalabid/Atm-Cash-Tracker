import 'package:cloud_firestore/cloud_firestore.dart';

/// One-time function to add 15 more ATMs across Dhaka.
/// Call once from _initData(), then remove the call.
Future<void> seedExpandedAtms() async {
  final booths = FirebaseFirestore.instance.collection('atm_booths');

  // Guard: skip if we already have more than the original 5.
  final snap = await booths.get();
  if (snap.docs.length > 5) {
    return; // already expanded
  }

  final batch = FirebaseFirestore.instance.batch();
  for (final atm in _expandedAtms) {
    batch.set(booths.doc(), atm);
  }
  await batch.commit();
}

final List<Map<String, dynamic>> _expandedAtms = [
  // ── Farmgate Area ──────────────────────────────────────
  {
    'bankName': 'Dutch-Bangla Bank',
    'address': 'Farmgate, Dhaka',
    'distance': '1.4 km away',
    'status': 'available',
    'queueLength': 'longLine',
    'notes': 'Both slots working. Heavy rush after 6 PM.',
    'latitude': 23.7575,
    'longitude': 90.3880,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Shahbagh ───────────────────────────────────────────
  {
    'bankName': 'Sonali Bank',
    'address': 'Shahbagh, Dhaka',
    'distance': '1.8 km away',
    'status': 'empty',
    'queueLength': 'noLine',
    'notes': 'Out of cash since morning. Security guard confirmed.',
    'latitude': 23.7385,
    'longitude': 90.3957,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Jatrabari ──────────────────────────────────────────
  {
    'bankName': 'Janata Bank',
    'address': 'Jatrabari, Dhaka',
    'distance': '4.2 km away',
    'status': 'low',
    'queueLength': 'shortLine',
    'notes': 'Only ৳1000 notes left.',
    'latitude': 23.7105,
    'longitude': 90.4340,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Banani ─────────────────────────────────────────────
  {
    'bankName': 'BRAC Bank',
    'address': 'Banani 11, Dhaka',
    'distance': '2.1 km away',
    'status': 'available',
    'queueLength': 'noLine',
    'notes': '',
    'latitude': 23.7937,
    'longitude': 90.4043,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Mohammadpur ────────────────────────────────────────
  {
    'bankName': 'Pubali Bank',
    'address': 'Mohammadpur, Dhaka',
    'distance': '2.8 km away',
    'status': 'low',
    'queueLength': 'longLine',
    'notes': 'Dispensing slowly. ৳500 notes only.',
    'latitude': 23.7655,
    'longitude': 90.3590,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Mirpur 2 ───────────────────────────────────────────
  {
    'bankName': 'Dutch-Bangla Bank',
    'address': 'Mirpur 2, Dhaka',
    'distance': '3.5 km away',
    'status': 'available',
    'queueLength': 'shortLine',
    'notes': 'Newly refilled around 2 PM.',
    'latitude': 23.8015,
    'longitude': 90.3545,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Gulshan 2 ──────────────────────────────────────────
  {
    'bankName': 'Standard Chartered',
    'address': 'Gulshan 2 Circle, Dhaka',
    'distance': '2.4 km away',
    'status': 'available',
    'queueLength': 'noLine',
    'notes': 'Air-conditioned booth. Both slots active.',
    'latitude': 23.7940,
    'longitude': 90.4195,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Motijheel (Shapla Chattar) ─────────────────────────
  {
    'bankName': 'HSBC',
    'address': 'Shapla Chattar, Motijheel, Dhaka',
    'distance': '3.0 km away',
    'status': 'empty',
    'queueLength': 'noLine',
    'notes': 'Machine screen shows error. Reported to bank.',
    'latitude': 23.7280,
    'longitude': 90.4215,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Uttara Sector 3 ────────────────────────────────────
  {
    'bankName': 'Mutual Trust Bank',
    'address': 'Uttara Sector 3, Dhaka',
    'distance': '5.1 km away',
    'status': 'available',
    'queueLength': 'shortLine',
    'notes': '',
    'latitude': 23.8670,
    'longitude': 90.3920,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Bashundhara ────────────────────────────────────────
  {
    'bankName': 'City Bank',
    'address': 'Bashundhara R/A, Dhaka',
    'distance': '3.8 km away',
    'status': 'low',
    'queueLength': 'shortLine',
    'notes': 'Cash running low. May run out within an hour.',
    'latitude': 23.8145,
    'longitude': 90.4275,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Panthapath ─────────────────────────────────────────
  {
    'bankName': 'AB Bank',
    'address': 'Panthapath, Dhaka',
    'distance': '1.6 km away',
    'status': 'available',
    'queueLength': 'longLine',
    'notes': 'Working fine but very crowded at peak hours.',
    'latitude': 23.7520,
    'longitude': 90.3850,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Shyamoli ───────────────────────────────────────────
  {
    'bankName': 'Bank Asia',
    'address': 'Shyamoli, Dhaka',
    'distance': '2.3 km away',
    'status': 'empty',
    'queueLength': 'noLine',
    'notes': 'Under maintenance since yesterday.',
    'latitude': 23.7740,
    'longitude': 90.3650,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Banasree ───────────────────────────────────────────
  {
    'bankName': 'Prime Bank',
    'address': 'Banasree, Dhaka',
    'distance': '3.2 km away',
    'status': 'available',
    'queueLength': 'noLine',
    'notes': 'Quiet area. Rarely crowded.',
    'latitude': 23.7620,
    'longitude': 90.4360,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Pallabi ────────────────────────────────────────────
  {
    'bankName': 'Southeast Bank',
    'address': 'Pallabi, Mirpur, Dhaka',
    'distance': '4.5 km away',
    'status': 'low',
    'queueLength': 'shortLine',
    'notes': 'Only dispensing ৳500 notes.',
    'latitude': 23.8280,
    'longitude': 90.3590,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
  // ── Tejgaon ────────────────────────────────────────────
  {
    'bankName': 'ONE Bank',
    'address': 'Tejgaon I/A, Dhaka',
    'distance': '1.9 km away',
    'status': 'available',
    'queueLength': 'shortLine',
    'notes': 'Near the highway exit. Easy to access.',
    'latitude': 23.7630,
    'longitude': 90.3920,
    'lastUpdated': FieldValue.serverTimestamp(),
  },
];
