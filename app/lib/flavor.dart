/// true only in the owner app: flutter build apk --flavor owner --dart-define=OWNER_APP=true
/// In the customer app this is false and all owner-mode code is left out of the build.
const kOwnerApp = bool.fromEnvironment('OWNER_APP');

/// Suits are switched off for launch (people keep their own clothes). The suit code stays in the project;
/// build with --dart-define=SUITS=true (and add assets/suits/ back to pubspec.yaml) to bring it back.
const kSuits = bool.fromEnvironment('SUITS');
