import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../engine/torrent_facade.dart';
import '../providers/app_providers.dart';

/// Branded launch screen.
///
/// It never waits on the download engine: the engine warms up in the
/// background while the intro plays, and any failure surfaces on the
/// Downloads screen with a retry affordance. This keeps cold starts fast
/// and immune to platform-specific engine issues.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    // Warm the engine without ever blocking navigation.
    unawaited(
      ref.read(engineReadyProvider.future).then<void>(
            (TorrentFacade _) {},
            onError: (Object _) {},
          ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    if (mounted) {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ScaleTransition(
                scale: CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutBack,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 128,
                    height: 128,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                  children: <TextSpan>[
                    TextSpan(text: 'POPCORN'),
                    TextSpan(
                      text: ' STUDIO',
                      style: TextStyle(color: AppTheme.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                AppConstants.splashTagline,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 36),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
