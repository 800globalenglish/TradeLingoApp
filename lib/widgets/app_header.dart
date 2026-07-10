import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget {
  final double height;

  const AppHeader({super.key, this.height = 50});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo/800logo.png',
      height: height,
    );
  }
}