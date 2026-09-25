import 'package:flutter/material.dart';

abstract final class Palette {
  static const ink = Color(0xFF242424);
  static const muted = Color(0xFF666666);
  static const line = Color(0xFFD3D3D3);
  static const soft = Color(0xFFF3F3F3);
}

class TitleCopy extends StatelessWidget {
  const TitleCopy(this.value, {this.center = false, super.key});
  final String value;
  final bool center;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      value,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: const TextStyle(
        fontSize: 30,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class BodyCopy extends StatelessWidget {
  const BodyCopy(this.value, {this.center = false, super.key});
  final String value;
  final bool center;
  @override
  Widget build(BuildContext context) => Text(
    value,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: const TextStyle(fontSize: 16, height: 1.5, color: Palette.muted),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton(
    this.label, {
    required this.onPressed,
    this.secondary = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
    return secondary
        ? OutlinedButton(
            onPressed: onPressed,
            style: style,
            child: Text(label, textAlign: TextAlign.center),
          )
        : FilledButton(
            onPressed: onPressed,
            style: style,
            child: Text(label, textAlign: TextAlign.center),
          );
  }
}

class HintCard extends StatelessWidget {
  const HintCard({required this.title, required this.body, super.key});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Palette.soft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Palette.muted,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(fontSize: 14, height: 1.5)),
      ],
    ),
  );
}

class WireframeImage extends StatelessWidget {
  const WireframeImage(this.name, {required this.height, super.key});
  final String name;
  final double height;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/figma/$name.png',
      height: height,
      width: double.infinity,
      fit: BoxFit.fill,
    ),
  );
}
