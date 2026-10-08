/// One line of the "what just happened" trace shown in the UI.
class TraceStep {
  const TraceStep(this.title, this.value, {this.danger = false});

  final String title;
  final String value;
  final bool danger;
}
