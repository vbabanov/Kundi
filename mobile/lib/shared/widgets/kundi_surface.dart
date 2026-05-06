import 'package:flutter/material.dart';

import '../theme/kundi_tokens.dart';

class KundiGradientBackground extends StatelessWidget {
  const KundiGradientBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = scheme.kundiBackground;
    final bottom = scheme.kundiSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
      ),
      child: child,
    );
  }
}

class KundiSectionCard extends StatelessWidget {
  const KundiSectionCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(
      horizontal: KundiSpace.sm,
      vertical: KundiSpace.xs,
    ),
    this.padding = const EdgeInsets.all(KundiSpace.sm),
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: KundiElevation.raised,
      margin: margin,
      shape: const RoundedRectangleBorder(borderRadius: KundiRadius.md),
      color: scheme.kundiSurface.withValues(alpha: 0.9),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class KundiSectionHeader extends StatelessWidget {
  const KundiSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.merge(KundiTypography.sectionTitle),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class KundiStateBody extends StatelessWidget {
  const KundiStateBody.loading({
    super.key,
    this.label = 'Loading...',
  })  : icon = null,
        onRetry = null;

  const KundiStateBody.empty({
    super.key,
    required this.label,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
  });

  const KundiStateBody.error({
    super.key,
    required this.label,
    this.onRetry,
  }) : icon = Icons.error_outline;

  final String label;
  final IconData? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KundiSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: KundiSpace.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: KundiSpace.sm),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KundiEmptyState extends StatelessWidget {
  const KundiEmptyState({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(KundiSpace.sm),
      child: Column(
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.kundiTextTertiary,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.kundiTextSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class KundiGradeBadge extends StatelessWidget {
  const KundiGradeBadge({
    super.key,
    required this.value,
  });

  final String value;

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: KundiRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        value.trim().isEmpty ? '-' : value.trim(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Color _gradeColor(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      return const Color(0xFF60A5FA);
    }
    if (parsed >= 8) {
      return KundiPalette.success;
    }
    if (parsed >= 5) {
      return KundiPalette.warning;
    }
    return KundiPalette.danger;
  }
}

class KundiPrimaryButton extends StatelessWidget {
  const KundiPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: KundiRadius.pill,
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: KundiRadius.pill,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

class KundiWhatsAppButton extends StatelessWidget {
  const KundiWhatsAppButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: KundiRadius.pill,
        gradient: LinearGradient(
          colors: [Color(0xFF25D366), Color(0xFF128C7E)],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: KundiRadius.pill,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

class KundiCircularStat extends StatelessWidget {
  const KundiCircularStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.kundiElevated.withValues(alpha: 0.9),
            border: Border.all(color: scheme.kundiBorder),
          ),
          child: Center(
            child: Icon(icon, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.kundiTextSecondary,
              ),
        ),
      ],
    );
  }
}

class KundiAttentionPulse extends StatefulWidget {
  const KundiAttentionPulse({
    super.key,
    required this.active,
    required this.child,
    this.color = const Color(0xFFE35D6A),
    this.borderRadius = KundiRadius.md,
  });

  final bool active;
  final Widget child;
  final Color color;
  final BorderRadius borderRadius;

  @override
  State<KundiAttentionPulse> createState() => _KundiAttentionPulseState();
}

class _KundiAttentionPulseState extends State<KundiAttentionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant KundiAttentionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncAnimationState();
    }
  }

  void _syncAnimationState() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final glowOpacity = 0.12 + (0.18 * t);
        final tintOpacity = 0.07 + (0.08 * t);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glowOpacity),
                blurRadius: 12 + (8 * t),
                spreadRadius: 0.5 + (1.2 * t),
              ),
            ],
          ),
          child: Stack(
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.borderRadius,
                      border: Border.all(
                        color: widget.color.withValues(alpha: 0.42),
                      ),
                      color: widget.color.withValues(alpha: tintOpacity),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
