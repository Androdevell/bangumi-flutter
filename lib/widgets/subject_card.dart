import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/network/app_image_cache.dart';
import '../data/bangumi_repository.dart';
import '../features/subject/subject_detail_page.dart';
import 'common.dart';

class SubjectCard extends StatelessWidget {
  const SubjectCard({
    super.key,
    required this.subject,
    required this.index,
    required this.repository,
  });

  final Subject subject;
  final int index;
  final BangumiRepository repository;

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  pageBuilder:
                      (_, animation, __) => SubjectDetailPage(
                        subject: subject,
                        heroTag: 'subject-$index',
                        repository: repository,
                      ),
                  transitionsBuilder: (_, animation, __, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
                  tag: 'subject-$index',
                  child: PosterArt(subject: subject, cacheWidth: 520),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
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
                        Text(subject.score.toStringAsFixed(1)),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            subject.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
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

class PosterArt extends StatelessWidget {
  const PosterArt({super.key, required this.subject, this.cacheWidth});

  final Subject subject;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    if (subject.imageUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: subject.imageUrl,
            cacheManager: AppImageCache.manager,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            maxWidthDiskCache: cacheWidth == null ? null : cacheWidth! * 2,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            placeholder: (_, __) => _PosterFallback(subject: subject),
            errorWidget: (_, __, ___) => _PosterFallback(subject: subject),
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
