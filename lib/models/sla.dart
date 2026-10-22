import 'models.dart';

enum SlaColor { green, amber, red }

/// Default SLA policy from the spec (Section 7.2). Secretary can change via W5.
class SlaThreshold {
  const SlaThreshold({required this.amberAfter, required this.redAfter, this.inHours = false});
  final int amberAfter;
  final int redAfter;
  final bool inHours;
}

const defaultSlaPolicy = <Criticality, SlaThreshold>{
  Criticality.critical: SlaThreshold(amberAfter: 2, redAfter: 6, inHours: true),
  Criticality.high: SlaThreshold(amberAfter: 1, redAfter: 3),
  Criticality.medium: SlaThreshold(amberAfter: 1, redAfter: 6),
  Criticality.low: SlaThreshold(amberAfter: 4, redAfter: 11),
};

class SlaInfo {
  const SlaInfo(this.color, this.ageLabel);
  final SlaColor color;
  final String ageLabel;
}

SlaInfo slaFor(Complaint c, DateTime now) {
  final t = defaultSlaPolicy[c.criticality]!;
  final from = c.acceptedAt ?? c.createdAt;
  if (t.inHours) {
    final h = now.difference(from).inHours;
    final color = h >= t.redAfter
        ? SlaColor.red
        : h >= t.amberAfter
        ? SlaColor.amber
        : SlaColor.green;
    return SlaInfo(color, '$h h');
  }
  final start = DateTime(from.year, from.month, from.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(start).inDays;
  final color = days >= t.redAfter
      ? SlaColor.red
      : days >= t.amberAfter
      ? SlaColor.amber
      : SlaColor.green;
  return SlaInfo(color, 'Day $days');
}

/// Keyword-based stand-in for the AI criticality classifier (spec Section 7.4).
class AiSuggestion {
  const AiSuggestion(this.criticality, this.category, this.reason);
  final Criticality criticality;
  final String category;
  final String reason;
}

AiSuggestion? suggestCriticality(String text) {
  final t = text.toLowerCase();
  if (t.trim().length < 6) return null;
  const rules = <(List<String>, Criticality, String)>[
    (['stuck', 'trapped'], Criticality.critical, 'Lift'),
    (['fire', 'smoke', 'spark', 'short circuit'], Criticality.critical, 'Electrical'),
    (['no water', 'water outage', 'flood'], Criticality.critical, 'Water supply'),
    (['theft', 'intruder', 'security breach'], Criticality.critical, 'Security'),
    (['pump', 'motor'], Criticality.high, 'Plumbing'),
    (['power', 'electric', 'light'], Criticality.high, 'Electrical'),
    (['lift', 'elevator'], Criticality.high, 'Lift'),
    (['leak', 'tap', 'drain', 'pipe'], Criticality.medium, 'Plumbing'),
    (['garbage', 'dirty', 'clean'], Criticality.medium, 'Cleaning'),
    (['noise', 'parking', 'pet'], Criticality.low, 'Community'),
    (['paint', 'suggest'], Criticality.low, 'Other'),
  ];
  for (final (words, crit, cat) in rules) {
    for (final w in words) {
      if (t.contains(w)) {
        return AiSuggestion(crit, cat, 'Mentions "$w"');
      }
    }
  }
  return const AiSuggestion(Criticality.medium, 'Other', 'No urgent keywords found');
}
