import 'package:flutter/material.dart';

class HabitEntry {
  const HabitEntry({
    required this.name,
    required this.icon,
    required this.current,
    required this.target,
    required this.unit,
    this.completed = false,
  });

  final String name;
  final IconData icon;
  final double current;
  final double target;
  final String unit;
  final bool completed;

  HabitEntry copyWith({bool? completed}) {
    return HabitEntry(
      name: name,
      icon: icon,
      current: current,
      target: target,
      unit: unit,
      completed: completed ?? this.completed,
    );
  }
}

class MoneyTransaction {
  const MoneyTransaction({
    required this.title,
    required this.category,
    required this.amount,
    required this.icon,
    this.isIncome = false,
  });

  final String title;
  final String category;
  final int amount;
  final IconData icon;
  final bool isIncome;
}
