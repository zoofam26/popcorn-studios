import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../providers/app_providers.dart';
import '../widgets/common.dart';

/// TMDB search with debounce, grid results and empty states.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 800;
    final AsyncValue<List<Movie>> results = _query.isEmpty
        ? const AsyncValue<List<Movie>>.data(<Movie>[])
        : ref.watch(searchProvider(_query));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search movies…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      body: _query.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.movie_filter_outlined,
                      size: 64, color: AppTheme.textSecondary),
                  const SizedBox(height: 12),
                  const Text(
                    'Find a movie to stream or download',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          : results.when(
              data: (List<Movie> movies) {
                if (movies.isEmpty) {
                  return const ErrorRetryView(
                      message: 'No movies matched your search.');
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: wide ? 190 : 130,
                    childAspectRatio: 0.52,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 18,
                  ),
                  itemCount: movies.length,
                  itemBuilder: (BuildContext context, int index) =>
                      PosterCard(movie: movies[index]),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (Object e, StackTrace s) => ErrorRetryView(
                message: 'Search failed: $e',
                onRetry: () => ref.invalidate(searchProvider(_query)),
              ),
            ),
    );
  }
}
