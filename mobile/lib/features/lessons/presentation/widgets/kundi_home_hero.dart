import 'package:flutter/material.dart';

class KundiHomeHero extends StatelessWidget {
  const KundiHomeHero({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.message,
    required this.assetPath,
    this.onTap,
    this.semanticState,
  });

  static const heroKey = Key('kundi-home-hero');
  static const assetKey = Key('kundi-home-hero-asset');

  final String title;
  final String dateLabel;
  final String message;
  final String assetPath;
  final VoidCallback? onTap;
  final String? semanticState;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      label: semanticState,
      button: onTap != null,
      child: Container(
        key: heroKey,
        height: 280,
        clipBehavior: Clip.none,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xD91C174B), Color(0xD90D1238)],
          ),
          border: Border.all(color: const Color(0x806E5AD7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x334C35CF),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              right: 12,
              top: 45,
              child: _HeroGlow(),
            ),
            const Positioned(left: 22, top: 22, child: _Sparkle(size: 7)),
            const Positioned(left: 132, top: 56, child: _Sparkle(size: 4)),
            Positioned(
              left: 20,
              top: 28,
              right: 158,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    dateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFBEB3E6),
                          fontSize: 13,
                          height: 1.2,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFE5DFFF),
                          fontSize: 15,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -20,
              top: -12,
              bottom: -95,
              width: 235,
              child: Image.asset(
                assetPath,
                key: assetKey,
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                filterQuality: FilterQuality.high,
                semanticLabel: 'Персонаж Kundi',
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }
    return GestureDetector(onTap: onTap, child: content);
  }
}

class _HeroGlow extends StatelessWidget {
  const _HeroGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x668B5CF6),
              blurRadius: 72,
              spreadRadius: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: 0.78,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFD7C8FF),
            borderRadius: BorderRadius.circular(1),
            boxShadow: const [
              BoxShadow(color: Color(0xFF8B5CF6), blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}
