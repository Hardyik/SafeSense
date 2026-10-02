import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show kPrimary, kPrimaryDark, kPrimaryLight, kDanger, kWarning, kSafe;
import 'theme/app_theme.dart' show AppSurfaces;
import 'services/api_service.dart';
import 'services/emergency_contacts_service.dart';
import 'services/location_sharing_service.dart';
import 'services/firestore_service.dart';

/// Official all-in-one and service-specific emergency numbers for India.
/// This app's shelter/report data (Nashik-area sample data in schema.sql)
/// and default coordinates elsewhere in the app indicate an India-focused
/// deployment — change this list if targeting a different country/region,
/// per the spec's "use appropriate official emergency numbers for the
/// configured target region" instruction.
const List<Map<String, String>> kEmergencyNumbers = [
  {'label': 'All-in-one Emergency', 'number': '112'},
  {'label': 'Police', 'number': '100'},
  {'label': 'Fire', 'number': '101'},
  {'label': 'Ambulance', 'number': '102'},
  {'label': 'Disaster Management', 'number': '108'},
  {'label': 'Women Helpline', 'number': '1091'},
];

class EmergencyModePage extends StatefulWidget {
  final String userId;
  const EmergencyModePage({super.key, required this.userId});

  @override
  State<EmergencyModePage> createState() => _EmergencyModePageState();
}

class _EmergencyModePageState extends State<EmergencyModePage> {
  bool _loadingLocation = true;
  bool _locationUnavailable = false;
  List<dynamic> _nearestShelters = [];
  bool _sharing = false;
  String? _shareId;
  DateTime? _shareExpiresAt;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadLocationAndShelters();
    if (widget.userId.isNotEmpty) {
      final active =
          await LocationSharingService.instance.getActiveShare(widget.userId);
      if (mounted && active != null) {
        setState(() {
          _sharing = true;
          _shareId = active['id'];
          _shareExpiresAt = active['expiresAt'] as DateTime?;
        });
      }
    }
  }

  Future<void> _loadLocationAndShelters() async {
    setState(() => _loadingLocation = true);
    // Resolve a position, falling back to the city centre (the same default
    // the dashboard uses) so the shelters section still works when the
    // browser blocks geolocation — e.g. laptop web with permission denied.
    double lat;
    double lng;
    bool located = true;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      lat = 19.2456;
      lng = 73.1300;
      located = false;
    }
    try {
      final shelters = await FirestoreService.instance.getShelters();
      shelters.sort((a, b) =>
          _distanceKm(lat, lng, a).compareTo(_distanceKm(lat, lng, b)));
      if (mounted) {
        setState(() {
          _locationUnavailable = !located;
          // Attach the client-computed haversine distance to each shelter.
          // The plain /shelters list endpoint does not include distance_km
          // (only /shelters/nearest and /shelters/nearby do), so without
          // this the subtitle cast used to crash on a null.
          _nearestShelters = shelters.take(3).map((s) {
            final d = _distanceKm(lat, lng, s);
            if (d.isFinite) s['distance_km'] = d;
            return s;
          }).toList();
          _loadingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  double _distanceKm(double fromLat, double fromLng, dynamic shelter) {
    final lat2 = (shelter['latitude'] as num?)?.toDouble();
    final lng2 = (shelter['longitude'] as num?)?.toDouble();
    if (lat2 == null || lng2 == null) return double.infinity;
    const r = 6371.0;
    final dLat = (lat2 - fromLat) * math.pi / 180;
    final dLon = (lng2 - fromLng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(fromLat * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer for $number')),
      );
    }
  }

  Future<void> _toggleSharing() async {
    if (widget.userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log in to share your location')),
      );
      return;
    }
    if (_sharing) {
      await LocationSharingService.instance.stopSharing();
      if (mounted) {
        setState(() {
          _sharing = false;
          _shareId = null;
          _shareExpiresAt = null;
        });
      }
      return;
    }

    final duration = await showDialog<Duration>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share location for how long?'),
        children: [
          for (final h in [1, 2, 4])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, Duration(hours: h)),
              child: Text('$h hour${h > 1 ? 's' : ''}'),
            ),
        ],
      ),
    );
    if (duration == null) return;

    try {
      final id = await LocationSharingService.instance.startSharing(
        userId: widget.userId,
        sharedWithUserIds: const [], // contact-based sharing, not yet linked to app accounts
        duration: duration,
      );
      if (mounted) {
        setState(() {
          _sharing = true;
          _shareId = id;
          _shareExpiresAt = DateTime.now().add(duration);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start sharing: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kDanger,
        foregroundColor: Colors.white,
        title: const Text('Emergency Mode',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadLocationAndShelters,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _sectionTitle('Emergency Services', Icons.local_hospital),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: kEmergencyNumbers.map((e) {
                return _CallButton(
                  label: e['label']!,
                  number: e['number']!,
                  onTap: () => _call(e['number']!),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            _sectionTitle('Live Alerts', Icons.campaign),
            _ActiveAlertsList(),

            const SizedBox(height: 24),
            _sectionTitle('Location Sharing', Icons.share_location),
            _LocationSharingCard(
              sharing: _sharing,
              expiresAt: _shareExpiresAt,
              onToggle: _toggleSharing,
            ),

            const SizedBox(height: 24),
            _sectionTitle('Nearest Shelters', Icons.home_work),
            if (_locationUnavailable)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Location unavailable — showing shelters nearest to the city centre',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppSurfaces.secondaryText(context)),
                ),
              ),
            if (_loadingLocation)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: kPrimary)),
              )
            else if (_nearestShelters.isEmpty)
              const _EmptyRow(text: 'No shelter data available yet')
            else
              ..._nearestShelters.map((s) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.home_work, color: kPrimary),
                      title: Text(s['name'] ?? 'Shelter'),
                      subtitle: Text(
                          '${s['distance_km'] == null ? 'Distance unknown' : '${(s['distance_km'] as num).toDouble().toStringAsFixed(1)} km away'} · ${s['status'] ?? 'unknown'}'),
                      trailing: s['contact'] != null && s['contact'] != 'N/A'
                          ? IconButton(
                              icon: const Icon(Icons.call, color: kSafe),
                              onPressed: () => _call(s['contact']),
                            )
                          : null,
                    ),
                  )),

            const SizedBox(height: 24),
            _sectionTitle('Emergency Contacts', Icons.contacts),
            _EmergencyContactsQuickList(userId: widget.userId, onCall: _call),

            const SizedBox(height: 24),
            _sectionTitle('Quick Safety Tips', Icons.checklist),
            const _SafetyTipsCard(),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _CallButton extends StatelessWidget {
  final String label;
  final String number;
  final VoidCallback onTap;
  const _CallButton(
      {required this.label, required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kDanger.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.call, color: kDanger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(number,
                        style: TextStyle(
                            color: AppSurfaces.secondaryText(context),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveAlertsList extends StatefulWidget {
  const _ActiveAlertsList();

  @override
  State<_ActiveAlertsList> createState() => _ActiveAlertsListState();
}

class _ActiveAlertsListState extends State<_ActiveAlertsList> {
  Timer? _timer;
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // The local API has no realtime snapshots — poll while the page is
    // open so newly published alerts appear without a manual refresh.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/api/alerts', auth: false);
      if (!mounted) return;
      setState(() {
        _alerts = (data['alerts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    if (_alerts.isEmpty) {
      return const _EmptyRow(text: 'No active alerts right now');
    }
    return Column(
      children: _alerts.map((a) {
        final severity = (a['severity'] ?? '').toString().toLowerCase();
        final color = severity == 'high' || severity == 'danger'
            ? kDanger
            : severity == 'moderate'
                ? kWarning
                : kPrimary;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: color.withOpacity(0.08),
          child: ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: color),
            title: Text(a['disasterType'] ?? 'Alert',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              [
                a['affectedArea'],
                a['description'],
              ].where((s) => s != null && s.toString().isNotEmpty).join(' — '),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LocationSharingCard extends StatelessWidget {
  final bool sharing;
  final DateTime? expiresAt;
  final VoidCallback onToggle;
  const _LocationSharingCard(
      {required this.sharing, required this.expiresAt, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(sharing ? Icons.location_on : Icons.location_off,
                    color: sharing ? kSafe : Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sharing
                        ? 'Sharing your location${expiresAt != null ? ' until ${TimeOfDay.fromDateTime(expiresAt!).format(context)}' : ''}'
                        : 'Not currently sharing location',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sharing
                  ? 'Keep the app open for location updates to keep sending — sharing stops automatically when it expires.'
                  : 'Starts a temporary share that automatically expires — nothing is tracked continuously otherwise.',
              style: TextStyle(
                  color: AppSurfaces.secondaryText(context), fontSize: 13),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onToggle,
                icon: Icon(sharing ? Icons.stop_circle : Icons.share_location),
                label: Text(sharing ? 'Stop sharing' : 'Start sharing'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: sharing ? kDanger : kPrimary,
                  side: BorderSide(color: sharing ? kDanger : kPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyContactsQuickList extends StatelessWidget {
  final String userId;
  final Future<void> Function(String number) onCall;
  const _EmergencyContactsQuickList(
      {required this.userId, required this.onCall});

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Log in to add emergency contacts'),
        ),
      );
    }
    return Column(
      children: [
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: EmergencyContactsService.instance.streamContacts(userId),
          builder: (context, snap) {
            final contacts = snap.data ?? [];
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: kPrimary)),
              );
            }
            if (contacts.isEmpty) {
              return const _EmptyRow(text: 'No emergency contacts added yet');
            }
            return Column(
              children: contacts.map((c) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: kPrimaryLight,
                        child: Icon(Icons.person, color: kPrimaryDark)),
                    title: Text(c['name'] ?? ''),
                    subtitle: Text([
                      if ((c['relationship'] ?? '').toString().isNotEmpty)
                        c['relationship'],
                      c['phone'],
                    ].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.call, color: kSafe),
                      onPressed: () => onCall(c['phone']),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => EmergencyContactsPage(userId: userId)),
            ),
            icon: const Icon(Icons.edit),
            label: const Text('Manage contacts'),
          ),
        ),
      ],
    );
  }
}


class _SafetyTipsCard extends StatelessWidget {
  const _SafetyTipsCard();

  @override
  Widget build(BuildContext context) {
    const tips = [
      'Stay calm and move away from the immediate hazard area.',
      'Keep your phone charged — use battery saver mode if power is limited.',
      'Follow official instructions over rumors or social media.',
      'If evacuating, take emergency contacts, medication, and ID with you.',
      'Avoid flooded or visibly damaged roads even if they look passable.',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: tips
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle,
                            color: kSafe, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  const _EmptyRow({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
          text, style: TextStyle(color: AppSurfaces.secondaryText(context))),
    );
  }
}

// ============================================================
// EMERGENCY CONTACTS MANAGEMENT (Section 9)
// ============================================================

class EmergencyContactsPage extends StatelessWidget {
  final String userId;
  const EmergencyContactsPage({super.key, required this.userId});

  void _showContactForm(BuildContext context, {Map<String, dynamic>? existing}) {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final phoneController = TextEditingController(text: existing?['phone'] ?? '');
    final relController =
        TextEditingController(text: existing?['relationship'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(existing == null ? 'Add contact' : 'Edit contact',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relController,
              decoration: const InputDecoration(
                  labelText: 'Relationship (optional)'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty ||
                      phoneController.text.trim().isEmpty) {
                    return;
                  }
                  if (existing == null) {
                    await EmergencyContactsService.instance.addContact(
                      userId: userId,
                      name: nameController.text,
                      phone: phoneController.text,
                      relationship: relController.text,
                    );
                  } else {
                    await EmergencyContactsService.instance.updateContact(
                      existing['id'],
                      name: nameController.text,
                      phone: phoneController.text,
                      relationship: relController.text,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimary,
        onPressed: () => _showContactForm(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: EmergencyContactsService.instance.streamContacts(userId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final contacts = snap.data!;
          if (contacts.isEmpty) {
            return Center(
              child: Text('No contacts yet — tap + to add one',
                  style: TextStyle(color: AppSurfaces.secondaryText(context))),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: contacts.length,
            itemBuilder: (context, i) {
              final c = contacts[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: kPrimaryLight,
                      child: Icon(Icons.person, color: kPrimaryDark)),
                  title: Text(c['name'] ?? ''),
                  subtitle: Text([
                    if ((c['relationship'] ?? '').toString().isNotEmpty)
                      c['relationship'],
                    c['phone'],
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () =>
                            _showContactForm(context, existing: c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: kDanger),
                        onPressed: () => EmergencyContactsService.instance
                            .deleteContact(c['id']),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
