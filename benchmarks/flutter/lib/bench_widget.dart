// The benchmark workload: 500 cards in a column, each a rounded
// rect background with two text labels. Same as the flit version
// in benchmarks/flit/bench.nim so the comparison is fair.

import 'package:flutter/material.dart';

class BenchWidget extends StatelessWidget {
  final int count;
  const BenchWidget({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Container(
        color: const Color(0xFFF5F5F8),
        // SingleChildScrollView lets the Column overflow the
        // viewport (same as flit's column). The comparison
        // measures full layout + paint of every card.
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(count, (i) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Item ${i + 1}',
                      style: const TextStyle(fontSize: 16, color: Colors.black)),
                  Text('subtitle line ${i + 1}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            );
          }),
        )),
      ),
    );
  }
}
