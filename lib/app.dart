import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'presentation/providers/app_providers.dart';

class PopcornStudioApp extends ConsumerStatefulWidget {
  const PopcornStudioApp({super.key});

  @override
  ConsumerState<PopcornStudioApp> createState() => _PopcornStudioAppState();
}

class _PopcornStudioAppState extends ConsumerState<PopcornStudioApp> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(settingsProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Popcorn Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
