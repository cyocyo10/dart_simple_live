import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A click opens the slider; muting remains a separate, explicit action.
/// A popup route also suspends the room's keyboard shortcuts while it is open.
class DesktopVolumeButton extends StatelessWidget {
  const DesktopVolumeButton({
    super.key,
    required this.volume,
    required this.onChanged,
    required this.onMute,
    this.onChangeEnd,
    this.onOpened,
    this.onClosed,
  });

  final RxDouble volume;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback onMute;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) => Obx(
        () => PopupMenuButton<void>(
          tooltip: '音量',
          position: PopupMenuPosition.over,
          requestFocus: true,
          onOpened: onOpened,
          onCanceled: onClosed,
          icon: Icon(
            volume.value == 0 ? Icons.volume_off : Icons.volume_down,
            size: 24,
            color: Colors.white,
          ),
          itemBuilder: (context) => [
            // The panel stays open while its slider and mute button are used.
            PopupMenuItem<void>(
              enabled: false,
              child: SizedBox(
                width: 260,
                child: Obx(
                  () => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('音量 ${volume.value.round()}%',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600))),
                        IconButton(
                          tooltip: volume.value == 0 ? '取消静音' : '静音',
                          onPressed: onMute,
                          icon: Icon(volume.value == 0
                              ? Icons.volume_off
                              : Icons.volume_up),
                        ),
                      ]),
                      Slider(
                        min: 0,
                        max: 100,
                        value: volume.value.clamp(0.0, 100.0),
                        label: '${volume.value.round()}%',
                        onChanged: onChanged,
                        onChangeEnd: onChangeEnd,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
