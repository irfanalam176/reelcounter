import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';

class BubbleStatusCard extends StatelessWidget {
  const BubbleStatusCard({
    super.key,
    required this.status,
    this.onEnableAccessibility,
    this.requestingAccessibility = false,
  });

  final BubbleStatus status;
  final VoidCallback? onEnableAccessibility;
  final bool requestingAccessibility;

  @override
  Widget build(BuildContext context) {
    final detectionActive = status.detectionState == 'active';
    final detectionError = status.detectionState == 'error';
    final detectionLabel = switch (status.detectionState) {
      'active' => 'Active',
      'error' => 'Error',
      'checking' => 'Checking…',
      _ => 'Waiting',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BUBBLE & TRACKING',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            _StatusRow(
              icon: Icons.bolt_rounded,
              label: 'Floating Bubble',
              value: status.serviceRunning ? 'Running' : 'Stopped',
              subtitle: status.serviceRunning
                  ? (status.bubbleVisible ? 'Bubble visible' : 'Bubble hidden')
                  : null,
              active: status.serviceRunning,
            ),
            _StatusRow(
              icon: Icons.accessibility_new_rounded,
              label: 'Accessibility Service',
              value: status.accessibilityEnabled ? 'Enabled' : 'Disabled',
              subtitle: status.accessibilityEnabled
                  ? (status.accessibilityServiceRunning
                      ? 'Detection service connected'
                      : 'Detection service not connected')
                  : 'Required for automatic detection',
              active: status.accessibilityEnabled,
            ),
            _StatusRow(
              icon: Icons.radar_outlined,
              label: 'Detection Engine',
              value: detectionLabel,
              subtitle: status.detectionMessage,
              active: detectionActive,
              error: detectionError,
            ),
            _StatusRow(
              icon: Icons.track_changes_outlined,
              label: 'Tracking',
              value: status.trackingActive ? 'Active' : 'Inactive',
              subtitle: status.trackingActive
                  ? null
                  : 'Requires a running bubble and active detection',
              active: status.trackingActive,
            ),
            if (!status.accessibilityEnabled && onEnableAccessibility != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: requestingAccessibility ? null : onEnableAccessibility,
                  icon: const Icon(Icons.settings_accessibility_rounded, size: 18),
                  label: Text(
                    requestingAccessibility ? 'Opening settings…' : 'Enable Accessibility',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    this.subtitle,
    this.error = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final String? subtitle;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final indicator = error ? AppColors.danger : active ? AppColors.green : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: active || error ? indicator : AppColors.muted, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: error ? AppColors.danger : AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: active || error ? indicator : AppColors.border,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
