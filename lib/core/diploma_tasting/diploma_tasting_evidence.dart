import 'dart:convert';

import 'diploma_tasting_flight.dart';

/// Self-reported physical practice only; it is not tasting accuracy or a pass.
class DiplomaTastingEvidence {
  const DiplomaTastingEvidence({
    this.d3Sessions = const {},
    this.d4Flights = 0,
    this.d5Flights = 0,
    this.unreadableCount = 0,
  });

  /// Distinct submitted D3 sessions; repeating one does not finish the pair.
  final Set<String> d3Sessions;
  final int d4Flights;
  final int d5Flights;
  final int unreadableCount;

  int forUnit(String unitId) => switch (unitId) {
    'D3' => d3Sessions.length,
    'D4' => d4Flights,
    'D5' => d5Flights,
    _ => 0,
  };
}

class DiplomaTastingEvidenceReader {
  static DiplomaTastingEvidence read(
    Map<String, String> settings, {
    required DateTime now,
  }) {
    final d3 = <String>{};
    var d4 = 0;
    var d5 = 0;
    var unreadable = 0;
    for (final entry in settings.entries) {
      if (!entry.key.startsWith(DiplomaTastingFlightRepository.flightPrefix)) {
        continue;
      }
      try {
        final row = Map<String, dynamic>.from(jsonDecode(entry.value) as Map);
        final flight = DiplomaTastingFlight.fromJson(row);
        if (DiplomaTastingFlightRepository.keyFor(flight.id) != entry.key) {
          throw const FormatException('Diploma tasting key mismatch.');
        }
        flight.validateAt(now);
        if (flight.isSubmitted) {
          if (flight.unitId == 'D3') d3.add(flight.sessionId);
          if (flight.unitId == 'D4') d4++;
          if (flight.unitId == 'D5') d5++;
        }
      } catch (_) {
        // This code only parses already-loaded settings. Other valid flights
        // still count; a corrupt row must never certify a physical tasting.
        unreadable++;
      }
    }
    return DiplomaTastingEvidence(
      d3Sessions: Set.unmodifiable(d3),
      d4Flights: d4,
      d5Flights: d5,
      unreadableCount: unreadable,
    );
  }
}
