/// Generates a locally-unique id for a new conversation turn. Calls in this
/// app are sequential (always awaited), so a microsecond timestamp is
/// sufficient — no need to pull in a UUID package for this.
String newTurnId() => DateTime.now().microsecondsSinceEpoch.toString();
