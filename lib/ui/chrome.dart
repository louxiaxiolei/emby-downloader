import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: cinema.glass,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: cinema.text, size: 22),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}

class EmbyImage extends StatelessWidget {
  const EmbyImage({
    super.key,
    required this.url,
    this.headers = const {},
    this.fit = BoxFit.cover,
  });

  final String url;
  final Map<String, String> headers;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    if (url.isEmpty) {
      return ColoredBox(color: cinema.dark ? const Color(0xFF2A2E36) : const Color(0xFFD5D0C6));
    }
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 220),
      placeholder: (context, url) => ColoredBox(color: cinema.line.withValues(alpha: 0.4)),
      errorWidget: (context, url, error) => ColoredBox(
        color: cinema.line.withValues(alpha: 0.45),
        child: Icon(Icons.image_not_supported_outlined, color: cinema.muted),
      ),
    );
  }
}

class ShelfHeader extends StatelessWidget {
  const ShelfHeader({super.key, required this.title, this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 8, 10),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cinema.text)),
          const Spacer(),
          if (onMore != null)
            IconButton(onPressed: onMore, icon: Icon(Icons.chevron_right, color: cinema.muted)),
        ],
      ),
    );
  }
}

class ServerPill extends StatelessWidget {
  const ServerPill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xF21B1E18),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: okGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
