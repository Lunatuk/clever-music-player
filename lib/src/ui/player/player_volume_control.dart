import 'dart:async';

import 'package:flutter/material.dart';

final class PlayerVolumeControl extends StatefulWidget {
  const PlayerVolumeControl({
    super.key,
    required this.volume,
    required this.showSlider,
    required this.onToggleMute,
    required this.onChanged,
  });

  final double volume;
  final bool showSlider;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onChanged;

  @override
  State<PlayerVolumeControl> createState() => _PlayerVolumeControlState();
}

final class _PlayerVolumeControlState extends State<PlayerVolumeControl> {
  static const double _popupWidth = 44;
  static const double _popupHeight = 154;
  static const double _popupGap = 3;

  OverlayEntry? _overlayEntry;
  Timer? _hideOverlayTimer;
  Rect? _buttonOverlayRect;
  bool _isButtonHovered = false;
  bool _isPopupHovered = false;
  bool _isPopupDragging = false;

  @override
  void didUpdateWidget(PlayerVolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSlider) {
      _hideOverlayNow();
      return;
    }
    _scheduleOverlayRebuild();
  }

  @override
  void dispose() {
    _hideOverlayTimer?.cancel();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedVolume = _normalizedVolumeForDisplay(widget.volume);
    final volumeIcon = _volumeIcon(normalizedVolume);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => _handleButtonHoverChanged(isHovered: true),
          onExit: (_) => _handleButtonHoverChanged(isHovered: false),
          child: IconButton(
            key: const ValueKey('bottom-player-volume-button'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            tooltip: widget.showSlider
                ? (normalizedVolume <= 0 ? 'Включить звук' : 'Выключить звук')
                : null,
            onPressed: widget.onToggleMute,
            icon: Icon(volumeIcon, size: 20),
          ),
        ),
        if (widget.showSlider) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 140,
            child: _VolumeSliderTheme(
              child: Slider(
                key: const ValueKey('bottom-player-volume-slider'),
                value: normalizedVolume,
                min: 0,
                max: 1,
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _handleButtonHoverChanged({required bool isHovered}) {
    _isButtonHovered = isHovered;
    if (isHovered) {
      _hideOverlayTimer?.cancel();
      _showOverlay();
      return;
    }

    _scheduleOverlayHide();
  }

  void _handlePopupHoverChanged({required bool isHovered}) {
    _isPopupHovered = isHovered;
    if (isHovered) {
      _hideOverlayTimer?.cancel();
      return;
    }

    _scheduleOverlayHide();
  }

  void _showOverlay() {
    if (widget.showSlider || _overlayEntry != null) {
      return;
    }
    if (!_updateButtonOverlayRect()) {
      return;
    }

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_overlayEntry!);
  }

  Widget _buildOverlay(BuildContext context) {
    final normalizedVolume = _normalizedVolumeForDisplay(widget.volume);
    final overlaySize = MediaQuery.sizeOf(context);
    final buttonRect = _buttonOverlayRect;
    if (buttonRect == null) {
      return const SizedBox.shrink();
    }

    final left = (buttonRect.center.dx - (_popupWidth / 2))
        .clamp(8.0, overlaySize.width - _popupWidth - 8)
        .toDouble();
    final top = (buttonRect.top - _popupHeight - _popupGap)
        .clamp(8.0, overlaySize.height - _popupHeight - 8)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: _popupWidth,
        height: _popupHeight,
        child: MouseRegion(
          onEnter: (_) => _handlePopupHoverChanged(isHovered: true),
          onExit: (_) => _handlePopupHoverChanged(isHovered: false),
          child: _VolumePopupSlider(
            value: normalizedVolume,
            onChanged: widget.onChanged,
            onChangeStart: (_) {
              _isPopupDragging = true;
              _hideOverlayTimer?.cancel();
            },
            onChangeEnd: (_) {
              _isPopupDragging = false;
              _scheduleOverlayHide();
            },
          ),
        ),
      ),
    );
  }

  void _scheduleOverlayHide() {
    _hideOverlayTimer?.cancel();
    _hideOverlayTimer = Timer(const Duration(milliseconds: 140), () {
      if (_isButtonHovered || _isPopupHovered || _isPopupDragging) {
        return;
      }
      _hideOverlayNow();
    });
  }

  void _hideOverlayNow() {
    _hideOverlayTimer?.cancel();
    _hideOverlayTimer = null;
    _isPopupHovered = false;
    _isPopupDragging = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _scheduleOverlayRebuild() {
    if (_overlayEntry == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateButtonOverlayRect();
      _overlayEntry?.markNeedsBuild();
    });
  }

  bool _updateButtonOverlayRect() {
    final renderBox = context.findRenderObject();
    final overlayRenderBox = Overlay.of(context).context.findRenderObject();
    if (renderBox is! RenderBox ||
        overlayRenderBox is! RenderBox ||
        !renderBox.attached ||
        !overlayRenderBox.attached) {
      return false;
    }

    final topLeft = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayRenderBox,
    );
    _buttonOverlayRect = topLeft & renderBox.size;
    return true;
  }
}

final class _VolumePopupSlider extends StatelessWidget {
  const _VolumePopupSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Material(
        key: const ValueKey('bottom-player-volume-popup'),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.94),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          child: SizedBox(
            width: 36,
            height: 144,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: RotatedBox(
                quarterTurns: -1,
                child: _VolumeSliderTheme(
                  child: Slider(
                    key: const ValueKey('bottom-player-volume-popup-slider'),
                    value: value,
                    min: 0,
                    max: 1,
                    onChanged: onChanged,
                    onChangeStart: onChangeStart,
                    onChangeEnd: onChangeEnd,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _VolumeSliderTheme extends StatelessWidget {
  const _VolumeSliderTheme({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),
      child: child,
    );
  }
}

IconData _volumeIcon(double volume) {
  if (volume <= 0) {
    return Icons.volume_off_outlined;
  }
  if (volume < 0.5) {
    return Icons.volume_down_outlined;
  }
  return Icons.volume_up_outlined;
}

double _normalizedVolumeForDisplay(double volume) {
  if (volume.isNaN) {
    return 1;
  }
  if (volume == double.infinity) {
    return 1;
  }
  if (volume == double.negativeInfinity) {
    return 0;
  }
  return volume.clamp(0.0, 1.0).toDouble();
}
