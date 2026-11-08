import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../emby/net_log.dart';
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

class EmbyImage extends StatefulWidget {
  const EmbyImage({
    super.key,
    this.url = '',
    this.urls = const [],
    this.headers = const {},
    this.fit = BoxFit.cover,
  });

  final String url;
  final List<String> urls;
  final Map<String, String> headers;
  final BoxFit fit;

  @override
  State<EmbyImage> createState() => _EmbyImageState();
}

class _EmbyImageState extends State<EmbyImage> {
  var _index = 0;

  List<String> get _urls {
    if (widget.urls.isNotEmpty) return widget.urls;
    if (widget.url.isNotEmpty) return [widget.url];
    return const [];
  }

  @override
  void didUpdateWidget(EmbyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.urls != widget.urls) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    final urls = _urls;
    if (urls.isEmpty || _index >= urls.length) {
      return ColoredBox(
        color: cinema.dark ? const Color(0xFF2A2E36) : const Color(0xFFD5D0C6),
        child: Icon(Icons.image_not_supported_outlined, color: cinema.muted),
      );
    }
    final current = urls[_index];
    return CachedNetworkImage(
      imageUrl: current,
      httpHeaders: widget.headers,
      fit: widget.fit,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (context, url) => ColoredBox(color: cinema.line.withValues(alpha: 0.35)),
      errorWidget: (context, url, error) {
        NetLog.instance.add('图片失败 ${NetLog.redact(Uri.parse(url))} $error');
        final next = _index + 1;
        if (next < urls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _index == next - 1) setState(() => _index = next);
          });
        }
        return ColoredBox(
          color: cinema.dark ? const Color(0xFF2A2E36) : const Color(0xFFD5D0C6),
          child: Icon(Icons.broken_image_outlined, color: cinema.muted),
        );
      },
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
  const ServerPill({super.key, required this.label, required this.onTap, this.onLongPress});

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
