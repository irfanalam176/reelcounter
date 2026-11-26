import 'package:flutter/material.dart';

import 'package:reelcount/services/floating_bubble_service.dart';
import 'package:reelcount/theme/app_theme.dart';

class BubbleStatusCard extends StatelessWidget {
  const BubbleStatusCard({
    super.key,
    required this.status,
    this.onEnableAccessibility,
    this.requestingAccessibility = false,
    this.onOpenBackgroundActivity,
    this.requestingBackgroundActivity = false,
    this.onEnableAutoBackgroundStart,
    this.requestingAutoBackgroundStart = false,
    this.onDisablePauseAppActivity,
    this.requestingPauseAppActivity = false,
    this.pauseAppActivityStatus = 'unknown',
  });

  final BubbleStatus status;
  final VoidCallback? onEnableAccessibility;
  final bool requestingAccessibility;
  final VoidCallback? onOpenBackgroundActivity;
  final bool requestingBackgroundActivity;
  final VoidCallback? onEnableAutoBackgroundStart;
  final bool requestingAutoBackgroundStart;
  final VoidCallback? onDisablePauseAppActivity;
  final bool requestingPauseAppActivity;
  final String pauseAppActivityStatus;

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
    final backgroundAllowed = status.backgroundActivityStatus == 'allowed';
    final backgroundLabel = switch (status.backgroundActivityStatus) {
      'allowed' => 'Allowed',
      'restricted' => 'Restricted',
      _ => 'Unknown',
    };
    final backgroundSubtitle = switch (status.backgroundActivityStatus) {
      'allowed' => 'Unrestricted battery usage is enabled.',
      'restricted' =>
        'Allow background activity or select Unrestricted battery usage in Android settings.',
      _ => 'This device does not expose a reliable background activity status.',
    };
    final pauseAppActivityLabel = switch (pauseAppActivityStatus) {
      'disabled' => 'Off',
      'enabled' => 'On',
      _ => 'Unknown',
    };
    final pauseAppActivitySubtitle = switch (pauseAppActivityStatus) {
      'disabled' => 'Pause app activity if unused is off for Scrollo.',
      'enabled' =>
        'Turn OFF Pause app activity if unused in Android App info.',
      _ => 'Check Pause app activity if unused in Android App info.',
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
              icon: Icons.battery_charging_full_outlined,
              label: 'Background Activity',
              value: backgroundLabel,
              subtitle: backgroundSubtitle,
              active: backgroundAllowed,
              error: status.backgroundActivityStatus == 'restricted',
            ),
            _StatusRow(
              icon: Icons.flash_on_outlined,
              label: 'Auto Background Start',
              value: 'Manual',
              subtitle: 'Enable Auto-start for Scrollo in your device settings.',
              active: false,
            ),
            _StatusRow(
              icon: Icons.pause_circle_outline,
              label: 'Pause App Activity If Unused',
              value: pauseAppActivityLabel,
              subtitle: pauseAppActivitySubtitle,
              active: pauseAppActivityStatus == 'disabled',
              error: pauseAppActivityStatus == 'enabled',
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
            if (!backgroundAllowed && onOpenBackgroundActivity != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: requestingBackgroundActivity ? null : onOpenBackgroundActivity,
                  icon: const Icon(Icons.battery_charging_full_outlined, size: 18),
                  label: Text(
                    requestingBackgroundActivity
                        ? 'Opening settings…'
                        : 'Allow Background Activity',
                  ),
                ),
              ),
            ],
            if (onEnableAutoBackgroundStart != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      requestingAutoBackgroundStart ? null : onEnableAutoBackgroundStart,
                  icon: const Icon(Icons.flash_on_outlined, size: 18),
                  label: Text(
                    requestingAutoBackgroundStart ? 'Opening settings…' : 'Enable',
                  ),
                ),
              ),
            ],
            if (onDisablePauseAppActivity != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      requestingPauseAppActivity ? null : onDisablePauseAppActivity,
                  icon: const Icon(Icons.pause_circle_outline, size: 18),
                  label: Text(
                    requestingPauseAppActivity ? 'Opening settings…' : 'Disable',
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
