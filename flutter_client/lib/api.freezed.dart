// Minimal stub generated manually to satisfy the `freezed` contract during development.
// Run `flutter pub run build_runner build` to regenerate this file with the
// official `freezed` output once the Flutter toolchain is installed.

part of 'api.dart';

mixin _$EngineBackend {}

class EngineBackend_Auto extends EngineBackend {
  const EngineBackend_Auto({required this.modelPath}) : super._();

  final String modelPath;

  @override
  int get hashCode => modelPath.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineBackend_Auto && other.modelPath == modelPath;
}

class EngineBackend_Piper extends EngineBackend {
  const EngineBackend_Piper(this.field0) : super._();

  final PiperBackendConfig field0;

  @override
  int get hashCode => field0.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineBackend_Piper && other.field0 == field0;
}
