import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/network/app_image_cache.dart';
import 'common.dart';
import '../core/localization/app_localizations.dart';

class SubjectCard extends StatelessWidget {
  const SubjectCard({
    super.key,
    required this.subject,
    required this.heroTag,
    required this.onTap,
  });

  final Subject subject;
  final String heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SubjectPosterHero(tag: heroTag, subject: subject),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: subject.title,
                      child: SizedBox(
                        height:
                            MediaQuery.textScalerOf(context).scale(16) * 2.7,
                        child: Text(
                          subject.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          subject.score > 0
                              ? subject.score.toStringAsFixed(1)
                              : '—',
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            subject.episodes > 0
                                ? '${subject.episodes} EP'
                                : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subject.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 两端共享解码尺寸和裁剪，飞行期间不重新按动画尺寸生成图片缓存键。
class SubjectPosterHero extends StatelessWidget {
  const SubjectPosterHero({
    super.key,
    required this.tag,
    required this.subject,
  });
  final String tag;
  final Subject subject;
  static const decodeWidth = 640;
  @override
  Widget build(BuildContext context) => Hero(
    tag: tag,
    flightShuttleBuilder: (context, animation, direction, from, to) {
      final hero =
          (direction == HeroFlightDirection.push ? from : to).widget as Hero;
      return hero.child;
    },
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: PosterArt(subject: subject, cacheWidth: decodeWidth),
    ),
  );
}

class PosterArt extends StatefulWidget {
  const PosterArt({super.key, required this.subject, this.cacheWidth});

  final Subject subject;
  final int? cacheWidth;

  @override
  State<PosterArt> createState() => _PosterArtState();
}

class _PosterArtState extends State<PosterArt> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final cacheWidth = widget.cacheWidth;
    if (subject.imageUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            key: ValueKey(_revision),
            imageUrl: subject.imageUrl,
            cacheManager: AppImageCache.manager,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            maxWidthDiskCache: cacheWidth == null ? null : cacheWidth * 2,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            placeholder: (_, __) => _PosterFallback(subject: subject),
            errorWidget:
                (_, __, ___) => Stack(
                  fit: StackFit.expand,
                  children: [
                    _PosterFallback(subject: subject),
                    Center(
                      child: IconButton.filledTonal(
                        tooltip:
                            Localizations.of<AppLocalizations>(
                              context,
                              AppLocalizations,
                            )?.t('posterFailed') ??
                            'Retry cover',
                        onPressed: () async {
                          await AppImageCache.manager.removeFile(
                            subject.imageUrl,
                          );
                          if (mounted) setState(() => _revision++);
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ),
          ),
          if (subject.hasProgress) _ProgressBadge(subject: subject),
        ],
      );
    }
    return _PosterFallback(subject: subject);
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: subject.colors,
            ),
          ),
        ),
        Positioned(
          right: -28,
          top: -24,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
        ),
        Positioned(
          left: -34,
          bottom: -30,
          child: Transform.rotate(
            angle: -0.35,
            child: Container(
              width: 130,
              height: 82,
              color: Colors.black.withValues(alpha: 0.12),
            ),
          ),
        ),
        Center(
          child: Icon(
            subject.symbol,
            size: 64,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
        if (subject.hasProgress) _ProgressBadge(subject: subject),
      ],
    );
  }
}

class _ProgressBadge extends StatelessWidget {
  const _ProgressBadge({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      bottom: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '${subject.progress} / ${subject.episodes}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
