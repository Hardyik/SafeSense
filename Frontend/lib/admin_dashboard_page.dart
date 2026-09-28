import 'package:flutter/material.dart';
import 'main.dart' show kPrimary, kDanger, kWarning, kSafe;
import 'theme/app_theme.dart' show AppSurfaces;
import 'services/admin_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Reports'),
            Tab(text: 'Alerts'),
            Tab(text: 'Shelters'),
            Tab(text: 'Risk Zones'),
            Tab(text: 'Admins'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ReportsTab(),
          _AlertsTab(),
          _SheltersTab(),
          _RiskZonesTab(),
          _AdminsTab(),
        ],
      ),
    );
  }
}

// ============================================================
// REPORTS — verify/reject pending community reports (Section 18)
// ============================================================

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: AdminService.instance.streamPendingReports(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: kPrimary));
        }
        final reports = snap.data!;
        if (reports.isEmpty) {
          return Center(
            child: Text('No pending reports',
                style: TextStyle(color: AppSurfaces.secondaryText(context))),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          itemBuilder: (context, i) {
            final r = reports[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((r['imageUrl'] as String?)?.isNotEmpty == true)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(r['imageUrl'],
                            height: 160, width: double.infinity, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${r['damageType'] ?? 'Unknown'} · ${r['severity'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                        'Confidence: ${(((r['confidence'] ?? 0) as num) * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: AppSurfaces.secondaryText(context),
                            fontSize: 12)),
                    if ((r['description'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(r['description']),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: kDanger,
                                side: const BorderSide(color: kDanger)),
                            onPressed: () => AdminService.instance
                                .setReportStatus(r['id'], 'rejected'),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: kSafe),
                            onPressed: () => AdminService.instance
                                .setReportStatus(r['id'], 'verified'),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Verify'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================
// ALERTS (Section 11)
// ============================================================

class _AlertsTab extends StatelessWidget {
  const _AlertsTab();

  void _showCreateForm(BuildContext context) {
    final typeController = TextEditingController();
    final areaController = TextEditingController();
    final descController = TextEditingController();
    final actionController = TextEditingController();
    String severity = 'moderate';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Emergency Alert',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                    controller: typeController,
                    decoration: const InputDecoration(
                        labelText: 'Disaster type (e.g. Flood)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => setModalState(() => severity = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: areaController,
                    decoration: const InputDecoration(labelText: 'Affected area')),
                const SizedBox(height: 12),
                TextField(
                    controller: descController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 12),
                TextField(
                    controller: actionController,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Recommended action')),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (typeController.text.trim().isEmpty) return;
                      await AdminService.instance.createAlert(
                        disasterType: typeController.text,
                        severity: severity,
                        affectedArea: areaController.text,
                        description: descController.text,
                        recommendedAction: actionController.text,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Publish Alert (sends push notification)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _severityColor(String s) {
    switch (s) {
      case 'high':
        return kDanger;
      case 'moderate':
        return kWarning;
      default:
        return kPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kDanger,
        onPressed: () => _showCreateForm(context),
        icon: const Icon(Icons.add_alert),
        label: const Text('New Alert'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: AdminService.instance.streamAlerts(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final alerts = snap.data!;
          if (alerts.isEmpty) {
            return Center(
                child: Text('No alerts yet',
                    style: TextStyle(color: Colors.grey.shade600)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: alerts.length,
            itemBuilder: (context, i) {
              final a = alerts[i];
              final active = a['status'] == 'active';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded,
                      color: _severityColor(a['severity'] ?? '')),
                  title: Text(a['disasterType'] ?? ''),
                  subtitle: Text('${a['affectedArea'] ?? ''} · ${a['status']}'),
                  trailing: active
                      ? TextButton(
                          onPressed: () =>
                              AdminService.instance.expireAlertNow(a['id']),
                          child: const Text('Expire now'),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// SHELTERS (Section 14)
// ============================================================

class _SheltersTab extends StatelessWidget {
  const _SheltersTab();

  void _showForm(BuildContext context, {Map<String, dynamic>? existing}) {
    final nameC = TextEditingController(text: existing?['name'] ?? '');
    final latC =
        TextEditingController(text: existing?['latitude']?.toString() ?? '');
    final lngC =
        TextEditingController(text: existing?['longitude']?.toString() ?? '');
    final capC =
        TextEditingController(text: existing?['capacity']?.toString() ?? '0');
    final occC = TextEditingController(
        text: existing?['occupancy']?.toString() ?? '0');
    final contactC = TextEditingController(text: existing?['contact'] ?? '');
    String status = existing?['status'] ?? 'available';
    String type = existing?['type'] ?? 'community';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'Add Shelter' : 'Edit Shelter',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: latC, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: lngC, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude'))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: capC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: occC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Occupancy'))),
                ]),
                const SizedBox(height: 12),
                TextField(controller: contactC, decoration: const InputDecoration(labelText: 'Contact number')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'available', child: Text('Available')),
                    DropdownMenuItem(value: 'full', child: Text('Full')),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  onChanged: (v) => setModalState(() => status = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'school', child: Text('School')),
                    DropdownMenuItem(value: 'government', child: Text('Government')),
                    DropdownMenuItem(value: 'community', child: Text('Community')),
                    DropdownMenuItem(value: 'emergency', child: Text('Emergency')),
                    DropdownMenuItem(value: 'warehouse', child: Text('Warehouse')),
                  ],
                  onChanged: (v) => setModalState(() => type = v!),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final lat = double.tryParse(latC.text);
                      final lng = double.tryParse(lngC.text);
                      if (nameC.text.trim().isEmpty || lat == null || lng == null) return;
                      await AdminService.instance.upsertShelter(
                        id: existing?['id'],
                        name: nameC.text,
                        latitude: lat,
                        longitude: lng,
                        capacity: int.tryParse(capC.text) ?? 0,
                        occupancy: int.tryParse(occC.text) ?? 0,
                        contact: contactC.text,
                        status: status,
                        type: type,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimary,
        onPressed: () => _showForm(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: AdminService.instance.streamShelters(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final shelters = snap.data!;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: shelters.length,
            itemBuilder: (context, i) {
              final s = shelters[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.home_work, color: kPrimary),
                  title: Text(s['name'] ?? ''),
                  subtitle: Text('${s['type']} · ${s['occupancy']}/${s['capacity']} · ${s['status']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showForm(context, existing: s),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: kDanger),
                        onPressed: () => AdminService.instance.deleteShelter(s['id']),
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

// ============================================================
// RISK ZONES (Section 12) — simplified center+radius authoring
// ============================================================

class _RiskZonesTab extends StatelessWidget {
  const _RiskZonesTab();

  void _showForm(BuildContext context) {
    final latC = TextEditingController();
    final lngC = TextEditingController();
    final radiusC = TextEditingController(text: '2');
    final typeC = TextEditingController();
    String riskLevel = 'moderate';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Risk Zone',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Simplified authoring: creates a square zone around a center point. A freehand polygon editor is future work.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextField(controller: latC, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Center latitude'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: lngC, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Center longitude'))),
                ]),
                const SizedBox(height: 12),
                TextField(controller: radiusC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Radius (km)')),
                const SizedBox(height: 12),
                TextField(controller: typeC, decoration: const InputDecoration(labelText: 'Disaster type (e.g. Flood)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: riskLevel,
                  decoration: const InputDecoration(labelText: 'Risk level'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => setModalState(() => riskLevel = v!),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final lat = double.tryParse(latC.text);
                      final lng = double.tryParse(lngC.text);
                      final radius = double.tryParse(radiusC.text);
                      if (lat == null || lng == null || radius == null) return;
                      await AdminService.instance.createSquareRiskZone(
                        centerLat: lat,
                        centerLng: lng,
                        radiusKm: radius,
                        riskLevel: riskLevel,
                        disasterType: typeC.text,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Create Zone'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: kWarning,
        onPressed: () => _showForm(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: AdminService.instance.streamRiskZones(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final zones = snap.data!;
          if (zones.isEmpty) {
            return Center(
                child: Text('No risk zones yet',
                    style: TextStyle(color: Colors.grey.shade600)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: zones.length,
            itemBuilder: (context, i) {
              final z = zones[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: kWarning),
                  title: Text('${z['disasterType'] ?? 'Zone'} · ${z['riskLevel']}'),
                  subtitle: Text('Status: ${z['status'] ?? ''}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: kDanger),
                    onPressed: () => AdminService.instance.deleteRiskZone(z['id']),
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

// ============================================================
// ADMINS — promote another user (Section 23)
// ============================================================

class _AdminsTab extends StatefulWidget {
  const _AdminsTab();

  @override
  State<_AdminsTab> createState() => _AdminsTabState();
}

class _AdminsTabState extends State<_AdminsTab> {
  final _uidController = TextEditingController();
  bool _loading = false;
  String? _message;

  Future<void> _promote() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await AdminService.instance.promoteToAdmin(uid);
      setState(() => _message = 'Promoted successfully. They may need to '
          'sign out and back in for it to take effect.');
      _uidController.clear();
    } catch (e) {
      setState(() => _message = 'Failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Promote a user to admin',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Enter the user\'s numeric user_id — shown in the list below (MySQL user table).',
            style: TextStyle(
                color: AppSurfaces.secondaryText(context), fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _uidController,
            decoration: const InputDecoration(labelText: 'User ID (numeric)'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _promote,
              child: _loading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Promote to Admin'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
