/// Single source of truth for the app's on-disk storage folder name — see
/// `StorageLocationService`. Never hardcode this string a second time
/// anywhere else.
///
/// Not derived from `package_info_plus` on purpose: that would make every
/// file path resolution in the app depend on an async platform-channel
/// call before it could even build a path string, for a value that's
/// static for the life of a release anyway. Kept in sync BY CONVENTION
/// with the platform-level app name (MaterialApp title in main.dart,
/// Windows window title in windows/runner/main.cpp, Android
/// android:label) — none of those read this constant back, since each is
/// its own platform's static metadata, so if the app is ever renamed
/// again, update all of those plus this one.
const String kAppFolderName = 'La Fly';
