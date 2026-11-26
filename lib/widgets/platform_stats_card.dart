import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';

class PlatformStatsCard extends StatelessWidget {
  const PlatformStatsCard({super.key, required this.counter});

  final BubbleCounter counter;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BY PLATFORM',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            ...ReelPlatform.values.map(
              (platform) => _PlatformRow(
                platform: platform,
                count: counter.countFor(platform),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({required this.platform, required this.count});

  final ReelPlatform platform;
  final int count;

  @override
  Widget build(BuildContext context) {
    final config = _platformConfig(platform);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(config.icon, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              config.label,
              style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            count.toString(),
            style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  _PlatformConfig _platformConfig(ReelPlatform platform) => switch (platform) {
        ReelPlatform.instagram => const _PlatformConfig('Instagram', Icons.photo_camera_outlined),
        ReelPlatform.youtube => const _PlatformConfig('YouTube Shorts', Icons.smart_display_outlined),
        ReelPlatform.facebook => const _PlatformConfig('Facebook Reels', Icons.facebook_outlined),
        ReelPlatform.tiktok => const _PlatformConfig('TikTok', Icons.music_note_outlined),
        ReelPlatform.snapchat => const _PlatformConfig('Snapchat Spotlight', Icons.bolt_outlined),
      };
}

class _PlatformConfig {
  const _PlatformConfig(this.label, this.icon);

  final String label;
  final IconData icon;
}
