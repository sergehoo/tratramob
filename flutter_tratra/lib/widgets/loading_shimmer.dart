// lib/widgets/loading_shimmer.dart
// Adaptateur : préférer TratraSkeletonList (lib/design) pour tout nouveau code.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Squelette de la liste de réservations (6 cartes), défilable comme l'ancienne ListView
/// pour rester compatible avec RefreshIndicator.
class BookingListShimmer extends StatelessWidget {
  const BookingListShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: TratraSkeletonList(count: 6),
    );
  }
}
