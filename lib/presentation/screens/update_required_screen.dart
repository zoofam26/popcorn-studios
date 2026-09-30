import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/update_service.dart';
import '../providers/app_providers.dart';

/// Full-screen gate shown when a newer release exists. The router locks
/// every other route away while this is active — the installed build simply
/// cannot be used past this point.
class UpdateRequiredScreen extends ConsumerStatefulWidget {
  const UpdateRequiredScreen({super.key});

  @override
  ConsumerState<UpdateRequiredScreen> createState() =>
      _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends ConsumerState<UpdateRequiredScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      ref.invalidate(updateGateProvider);
      final UpdateStatus status = await ref.read(updateGateProvider.future);
      if (!mounted) return;
      if (!status.updateRequired) {
        context.go('/splash');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Version ${status.latestVersion ?? ''} is still the latest '
              'release. Please install it to continue.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _openDownloadPage(String? url) async {
    final Uri uri =
        Uri.parse((url != null && url.isNotEmpty) ? url : AppConstants.releasePageUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open the browser. Visit:\n$uri'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final UpdateStatus? status = ref.watch(updateGateProvider).value;
    final String latest = status?.latestVersion ?? 'a newer release';
    final String current = status?.currentVersion ?? AppConstants.appVersion;

    return PopScope<bool>(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Update required',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Popcorn Studio $latest is now available. This version '
                      '($current) can no longer play or download — install '
                      'the latest release to keep watching.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () =>
                          _openDownloadPage(status?.releaseUrl),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text(
                        'Get the latest version',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _retrying ? null : _retry,
                      icon: _retrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text("I've updated — check again"),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Your downloads stay safely on this device and are '
                      'picked up by the new version automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
