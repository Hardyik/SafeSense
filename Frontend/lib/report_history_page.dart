import 'package:flutter/material.dart';

import 'main.dart' show kPrimary, kDanger, kWarning, kSafe;
import 'theme/app_theme.dart' show AppSurfaces;
import 'services/firestore_service.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'verified':
      return kSafe;
    case 'rejected':
      return kDanger;
    default:
      return kWarning; // pending
  }
}

IconData _statusIcon(String status) {
  switch (status) {
    case 'verified':
      return Icons.verified;
    case 'rejected':
      return Icons.cancel_outlined;
    default:
      return Icons.hourglass_top;
  }
}

class ReportHistoryPage extends StatefulWidget {
  final String userId;
  const ReportHistoryPage({super.key, required this.userId});

  @override
  State<ReportHistoryPage> createState() => _ReportHistoryPageState();
}

class _ReportHistoryPageState extends State<ReportHistoryPage> {
  List<dynamic> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final reports =
        await FirestoreService.instance.getUserReports(widget.userId);
    if (mounted) {
      setState(() {
        _reports = reports;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _reports.isEmpty
              ? Center(
                  child: Text('No reports submitted yet',
                      style: TextStyle(color: AppSurfaces.secondaryText(context))),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reports.length,
                    itemBuilder: (context, i) {
                      final r = _reports[i];
                      final status = (r['status'] ?? 'pending') as String;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Icon(_statusIcon(status),
                              color: _statusColor(status)),
                          title: Text(_titleCase(r['damage_type'] ?? 'Unknown')),
                          subtitle: Text(
                            r['created_at'] != null
                                ? _formatDate(r['created_at'])
                                : 'Date unknown',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _titleCase(status),
                              style: TextStyle(
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ReportDetailPage(report: r)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class ReportDetailPage extends StatelessWidget {
  final Map<String, dynamic> report;
  const ReportDetailPage({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final status = (report['status'] ?? 'pending') as String;

    return Scaffold(
      appBar: AppBar(title: const Text('Report Detail')),
      body: FutureBuilder<Map<String, dynamic>?>(
        // List items come from FirestoreService's legacy-shaped map (no
        // imageUrl in it). Fetch the full report here for the fields that
        // map intentionally leaves out.
        future: FirestoreService.instance.getReportDetail('${report['id']}'),
        builder: (context, snap) {
          final full = snap.data;
          final imageUrl = full?['imageUrl'] as String?;
          final description = full?['description'] as String? ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    imageUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) =>
                        progress == null
                            ? child
                            : const SizedBox(
                                height: 220,
                                child: Center(
                                    child: CircularProgressIndicator(
                                        color: kPrimary))),
                    errorBuilder: (ctx, err, st) => Container(
                      height: 220,
                      color: Theme.of(context).cardColor,
                      child: const Center(
                          child: Icon(Icons.broken_image, size: 48)),
                    ),
                  ),
                )
              else
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                      child: Text('No image on file for this report',
                          style: TextStyle(
                              color: AppSurfaces.secondaryText(context)))),
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(status),
                        size: 16, color: _statusColor(status)),
                    const SizedBox(width: 6),
                    Text(
                      status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _detailRow('Hazard type', report['damage_type'] ?? 'Unknown', context),
              _detailRow('Severity', report['hazard_level'] ?? 'Unknown', context),
              _detailRow('Road status', report['road_status'] ?? 'Unknown', context),
              _detailRow('Confidence',
                  '${(((report['confidence'] ?? 0) as num) * 100).toStringAsFixed(0)}%', context),
              if (description.isNotEmpty)
                _detailRow('Notes', description, context),
              const SizedBox(height: 8),
              Text(
                'AI-detected results are estimates, not a guarantee — always '
                'use your own judgment about the actual hazard.',
                style: TextStyle(
                    color: AppSurfaces.secondaryText(context), fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value, BuildContext context) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      color: AppSurfaces.secondaryText(context),
                      fontWeight: FontWeight.w500)),
            ),
            Expanded(
                child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
