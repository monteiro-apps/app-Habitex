import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habitex/theme/habitex_design.dart';

class HabitexAuthField extends StatelessWidget {
  const HabitexAuthField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HabitexSpacing.md),
      decoration: BoxDecoration(
        color: HabitexColors.surface,
        borderRadius: BorderRadius.circular(HabitexRadii.compact),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: HabitexColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  style: const TextStyle(
                    color: HabitexColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (suffixIcon != null) ...[
                const SizedBox(width: HabitexSpacing.xs),
                suffixIcon!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class HabitexPasswordVisibilityButton extends StatelessWidget {
  const HabitexPasswordVisibilityButton({
    super.key,
    required this.visible,
    required this.onTap,
  });

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(HabitexSpacing.xxs),
        child: Icon(
          visible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
          color: HabitexColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }
}
