import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../storage/database.dart';
import '../storage/storage_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  final StorageService storageService;

  const DiagnosticsScreen({super.key, required this.storageService});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, int> _counts = {};
  Map<String, dynamic> _syncStats = {};
  bool _loading = true;
  bool _exporting = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    setState(() => _loading = true);
    final db = await AppDatabase.instance.database;

    final counts = <String, int>{};

    counts['sessions'] = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM dim_App_Session'),
        ) ??
        0;

    counts['biosignals'] = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM dim_App_biosignals'),
        ) ??
        0;

    counts['emotions'] = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM dim_emotions'),
        ) ??
        0;

    counts['apps'] = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM dim_app'),
        ) ??
        0;

    counts['devices'] = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM dim_devices'),
        ) ??
        0;

    // Load sync stats
    final syncService = widget.storageService.syncService;
    if (syncService != null) {
      final stats = await syncService.getSyncStats();
      _syncStats = stats;
    }

    if (mounted) {
      setState(() {
        _counts = counts;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Diagnostics'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCounts,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.storage_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Database Statistics',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildStatRow('Sessions', _counts['sessions'] ?? 0),
                            _buildStatRow(
                                'Biosignals', _counts['biosignals'] ?? 0),
                            _buildStatRow('Emotions', _counts['emotions'] ?? 0),
                            _buildStatRow('Apps', _counts['apps'] ?? 0),
                            _buildStatRow('Devices', _counts['devices'] ?? 0),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_sync_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Cloud Sync',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (_syncStats.isNotEmpty) ...[
                              _buildStatRow(
                                  'Total Sessions', _syncStats['total'] ?? 0),
                              _buildStatRow(
                                  'Synced', _syncStats['synced'] ?? 0),
                              _buildStatRow(
                                  'Unsynced', _syncStats['unsynced'] ?? 0),
                              const SizedBox(height: 16),
                            ],
                            Text(
                              'Sync your session data to the SWIP cloud API. Make sure you have configured your API key.',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _syncing
                                        ? null
                                        : () => _configureApiKey(context),
                                    icon: const Icon(Icons.key_rounded),
                                    label: const Text('API Key'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _syncing ? null : _syncToCloud,
                                    icon: _syncing
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.white),
                                            ),
                                          )
                                        : const Icon(
                                            Icons.cloud_upload_rounded),
                                    label:
                                        Text(_syncing ? 'Syncing...' : 'Sync'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.file_download_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Export Database',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Export the SQLite database to view it with tools like DB Browser for SQLite, SQLite Studio, or any SQLite viewer.',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _exporting ? null : _exportDatabase,
                                icon: _exporting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.share_rounded),
                                label: Text(_exporting
                                    ? 'Exporting...'
                                    : 'Export Database'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _exportDatabase() async {
    setState(() => _exporting = true);

    try {
      // Export database to temporary location
      final exportPath = await AppDatabase.instance.exportDatabase();

      // Share the file
      await Share.shareXFiles(
        [XFile(exportPath)],
        text: 'SWIP Example Database Export',
        subject: 'swip_example.db',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database exported successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export database: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _configureApiKey(BuildContext context) async {
    final syncService = widget.storageService.syncService;
    if (syncService == null) return;

    final hasKey = await syncService.hasApiKey();
    final currentKey =
        hasKey ? await syncService.apiKeyStorage.getApiKey() : null;

    final controller = TextEditingController(text: currentKey ?? '');

    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API Key Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter your SWIP API key. This will be stored securely on your device.',
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk_live_...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (hasKey)
            TextButton(
              onPressed: () async {
                await syncService.apiKeyStorage.deleteApiKey();
                await syncService.initialize(); // Reinitialize to clear client
                Navigator.pop(context, 'deleted');
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result is String && result != 'deleted') {
        await syncService.setApiKey(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('API key saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result == 'deleted') {
        // Key was deleted
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('API key deleted'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  Future<void> _syncToCloud() async {
    final syncService = widget.storageService.syncService;
    if (syncService == null) {
      _showError('Sync service not available');
      return;
    }

    final hasKey = await syncService.hasApiKey();
    if (!hasKey) {
      _showError('Please configure your API key first');
      return;
    }

    if (!widget.storageService.cloudSyncConsentEnabled) {
      _showError(
          'Cloud sync consent is required. Please enable it in settings.');
      return;
    }

    setState(() => _syncing = true);

    try {
      final summary = await syncService.syncAllSessions(
        onSessionComplete: (sessionId, result) {
          // You can handle per-session completion here if needed
          log('Session $sessionId sync result: ${result.success}');
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync complete: ${summary.successful} successful, ${summary.failed} failed',
            ),
            backgroundColor: summary.failed == 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Reload stats
      await _loadCounts();
    } catch (e) {
      _showError('Sync failed: $e');
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildStatRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
