import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/news_item_model.dart';

class NewsArticleCard extends StatelessWidget {
  const NewsArticleCard({super.key, required this.article});
  final NewsItem article;

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.primaryDeep.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageURL.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: article.imageURL,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.primaryDeep.withValues(alpha: 0.4),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.primaryDeep.withValues(alpha: 0.4),
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: AppColors.textSecondary, size: 32),
                        ),
                      ),
                    ),
                    // Bottom gradient for legibility (in case category chip overlaps)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.4),
                            ],
                            stops: const [0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                    if (article.category.isNotEmpty)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            article.category.toUpperCase(),
                            style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      article.summary,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (article.sourceName.isNotEmpty)
                        Text(
                          article.sourceName,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      if (article.sourceName.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('·',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        ),
                      Text(
                        _timeAgo(article.publishedAt.toLocal()),
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.open_in_new_rounded,
                          size: 14, color: AppColors.textSecondary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
