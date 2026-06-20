import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen camera preview without stretching.
/// Uses the reported [CameraValue.previewSize] with a "cover" scale when available;
/// otherwise falls back to [CameraValue.aspectRatio] with a portrait heuristic.
class CameraPreviewFitted extends StatelessWidget {
  const CameraPreviewFitted({
    super.key,
    required this.controller,
  });

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        if (maxW <= 0 || maxH <= 0) {
          return const ColoredBox(color: Colors.black);
        }

        final pv = controller.value.previewSize;
        if (pv != null && pv.width > 0 && pv.height > 0) {
          final vw = pv.width;
          final vh = pv.height;
          final scale = math.max(maxW / vw, maxH / vh);
          return ClipRect(
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: vw,
                    height: vh,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            ),
          );
        }

        var ar = controller.value.aspectRatio;
        if (ar <= 0) {
          return ColoredBox(
            color: Colors.black,
            child: Center(child: CameraPreview(controller)),
          );
        }

        // Many devices report landscape buffer AR > 1; portrait UI needs the inverse height/width ratio.
        if (MediaQuery.orientationOf(context) == Orientation.portrait && ar > 1.0) {
          ar = 1.0 / ar;
        }

        late final double w;
        late final double h;
        if (maxW / maxH > ar) {
          h = maxH;
          w = h * ar;
        } else {
          w = maxW;
          h = w / ar;
        }

        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}
