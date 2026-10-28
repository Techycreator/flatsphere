/// Runs [action] while the app holds back the "Update available" prompt (web only; no-op elsewhere).
Future<T> runWithoutUpdatePrompt<T>(Future<T> Function() action) => action();
