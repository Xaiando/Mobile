// Web has no app-owned picker file path. Mobile and desktop builds use the
// guarded IO implementation; callers invoke it only for Android and iOS.
export 'picker_temp_cleanup_stub.dart'
    if (dart.library.io) 'picker_temp_cleanup_io.dart';
