import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/widgets/phone_call_icon.dart';
import 'package:linka/widgets/video_call_icon.dart';

void main() {
  testWidgets('render call icons side by side', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                PhoneCallIcon(size: 120, color: Colors.black, strokeWidth: 2),
                SizedBox(width: 24),
                VideoCallIcon(size: 120, color: Colors.black, strokeWidth: 2),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/claude-501/-Users-harry-projects-linka/6b15d040-9c3c-42e4-9b47-310ffa6c9bd2/scratchpad/icons.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
