import 'package:flutter/material.dart';

import 'package:reelcount/theme/app_theme.dart';

class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.granted,
    required this.requesting,
    required this.onEnable,
  });

  final bool granted;
  final bool requesting;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: granted ? AppColors.greenDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: granted ? AppColors.green : AppColors.border,
                ),
              ),
              child: Icon(
                granted ? Icons.verified_rounded : Icons.layers_outlined,
                color: granted ? AppColors.green : AppColors.muted,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    granted ? 'Overlay permission ready' : 'Overlay permission required',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    granted
                        ? 'ReelCount can display the bubble above Instagram, YouTube and other apps.'
                        : 'ReelCount needs “Display over other apps” so the counting bubble stays visible while you watch reels.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (!granted) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: requesting ? null : onEnable,
                        icon: requesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.settings_overscan_rounded, size: 18),
                        label: Text(requesting ? 'Opening settings…' : 'Enable Permission'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
