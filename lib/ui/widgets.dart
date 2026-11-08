import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../emby/api.dart';
import '../emby/models.dart';
import '../session_controller.dart';
import '../theme.dart';

class Poster extends StatelessWidget {
  const Poster({
    super.key,
    required this.url,
    required this.headers,
    this.aspect = 2 / 3,
    this.width,
    this.height,
  });

  final String url;
  final Map<String, String> headers;
  final double aspect;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final image = url.isEmpty
        ? const ColoredBox(
            color: panelHigh,
            child: Center(child: Icon(Icons.movie_outlined, color: muted)),
          )
        : CachedNetworkImage(
            imageUrl: url,
            httpHeaders: headers,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (context, url) => const ColoredBox(color: panelHigh),
            errorWidget: (context, url, error) => const ColoredBox(
              color: panelHigh,
              child: Icon(Icons.broken_image_outlined, color: muted),
            ),
          );
    final framed = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(color: panelHigh, child: image),
    );
    if (width != null || height != null) {
      return SizedBox(width: width, height: height, child: framed);
    }
    return AspectRatio(aspectRatio: aspect, child: framed);
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.message, this.icon = Icons.inbox_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }
}

class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 42, color: danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

Future<void> showMessage(BuildContext context, String message) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Future<T?> guardEmby<T>(BuildContext context, Future<T> action) async {
  try {
    return await action;
  } on EmbyUnauthorized {
    if (!context.mounted) return null;
    final navigator = Navigator.of(context);
    await context.read<SessionController>().invalidate();
    navigator.popUntil((route) => route.isFirst);
    return null;
  } catch (error) {
    if (context.mounted) await showMessage(context, friendlyError(error));
    return null;
  }
}
