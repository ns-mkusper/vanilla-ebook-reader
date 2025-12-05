// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$EngineBackend {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String modelPath) auto,
    required TResult Function(PiperBackendConfig field0) piper,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String modelPath)? auto,
    TResult? Function(PiperBackendConfig field0)? piper,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String modelPath)? auto,
    TResult Function(PiperBackendConfig field0)? piper,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(EngineBackend_Auto value) auto,
    required TResult Function(EngineBackend_Piper value) piper,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(EngineBackend_Auto value)? auto,
    TResult? Function(EngineBackend_Piper value)? piper,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(EngineBackend_Auto value)? auto,
    TResult Function(EngineBackend_Piper value)? piper,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EngineBackendCopyWith<$Res> {
  factory $EngineBackendCopyWith(
          EngineBackend value, $Res Function(EngineBackend) then) =
      _$EngineBackendCopyWithImpl<$Res, EngineBackend>;
}

/// @nodoc
class _$EngineBackendCopyWithImpl<$Res, $Val extends EngineBackend>
    implements $EngineBackendCopyWith<$Res> {
  _$EngineBackendCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EngineBackend
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$EngineBackend_AutoImplCopyWith<$Res> {
  factory _$$EngineBackend_AutoImplCopyWith(_$EngineBackend_AutoImpl value,
          $Res Function(_$EngineBackend_AutoImpl) then) =
      __$$EngineBackend_AutoImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String modelPath});
}

/// @nodoc
class __$$EngineBackend_AutoImplCopyWithImpl<$Res>
    extends _$EngineBackendCopyWithImpl<$Res, _$EngineBackend_AutoImpl>
    implements _$$EngineBackend_AutoImplCopyWith<$Res> {
  __$$EngineBackend_AutoImplCopyWithImpl(_$EngineBackend_AutoImpl _value,
      $Res Function(_$EngineBackend_AutoImpl) _then)
      : super(_value, _then);

  /// Create a copy of EngineBackend
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? modelPath = null,
  }) {
    return _then(_$EngineBackend_AutoImpl(
      modelPath: null == modelPath
          ? _value.modelPath
          : modelPath // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$EngineBackend_AutoImpl extends EngineBackend_Auto {
  const _$EngineBackend_AutoImpl({required this.modelPath}) : super._();

  @override
  final String modelPath;

  @override
  String toString() {
    return 'EngineBackend.auto(modelPath: $modelPath)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EngineBackend_AutoImpl &&
            (identical(other.modelPath, modelPath) ||
                other.modelPath == modelPath));
  }

  @override
  int get hashCode => Object.hash(runtimeType, modelPath);

  /// Create a copy of EngineBackend
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EngineBackend_AutoImplCopyWith<_$EngineBackend_AutoImpl> get copyWith =>
      __$$EngineBackend_AutoImplCopyWithImpl<_$EngineBackend_AutoImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String modelPath) auto,
    required TResult Function(PiperBackendConfig field0) piper,
  }) {
    return auto(modelPath);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String modelPath)? auto,
    TResult? Function(PiperBackendConfig field0)? piper,
  }) {
    return auto?.call(modelPath);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String modelPath)? auto,
    TResult Function(PiperBackendConfig field0)? piper,
    required TResult orElse(),
  }) {
    if (auto != null) {
      return auto(modelPath);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(EngineBackend_Auto value) auto,
    required TResult Function(EngineBackend_Piper value) piper,
  }) {
    return auto(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(EngineBackend_Auto value)? auto,
    TResult? Function(EngineBackend_Piper value)? piper,
  }) {
    return auto?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(EngineBackend_Auto value)? auto,
    TResult Function(EngineBackend_Piper value)? piper,
    required TResult orElse(),
  }) {
    if (auto != null) {
      return auto(this);
    }
    return orElse();
  }
}

abstract class EngineBackend_Auto extends EngineBackend {
  const factory EngineBackend_Auto({required final String modelPath}) =
      _$EngineBackend_AutoImpl;
  const EngineBackend_Auto._() : super._();

  String get modelPath;

  /// Create a copy of EngineBackend
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EngineBackend_AutoImplCopyWith<_$EngineBackend_AutoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$EngineBackend_PiperImplCopyWith<$Res> {
  factory _$$EngineBackend_PiperImplCopyWith(_$EngineBackend_PiperImpl value,
          $Res Function(_$EngineBackend_PiperImpl) then) =
      __$$EngineBackend_PiperImplCopyWithImpl<$Res>;
  @useResult
  $Res call({PiperBackendConfig field0});
}

/// @nodoc
class __$$EngineBackend_PiperImplCopyWithImpl<$Res>
    extends _$EngineBackendCopyWithImpl<$Res, _$EngineBackend_PiperImpl>
    implements _$$EngineBackend_PiperImplCopyWith<$Res> {
  __$$EngineBackend_PiperImplCopyWithImpl(_$EngineBackend_PiperImpl _value,
      $Res Function(_$EngineBackend_PiperImpl) _then)
      : super(_value, _then);

  /// Create a copy of EngineBackend
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$EngineBackend_PiperImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as PiperBackendConfig,
    ));
  }
}

/// @nodoc

class _$EngineBackend_PiperImpl extends EngineBackend_Piper {
  const _$EngineBackend_PiperImpl(this.field0) : super._();

  @override
  final PiperBackendConfig field0;

  @override
  String toString() {
    return 'EngineBackend.piper(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EngineBackend_PiperImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of EngineBackend
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EngineBackend_PiperImplCopyWith<_$EngineBackend_PiperImpl> get copyWith =>
      __$$EngineBackend_PiperImplCopyWithImpl<_$EngineBackend_PiperImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String modelPath) auto,
    required TResult Function(PiperBackendConfig field0) piper,
  }) {
    return piper(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String modelPath)? auto,
    TResult? Function(PiperBackendConfig field0)? piper,
  }) {
    return piper?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String modelPath)? auto,
    TResult Function(PiperBackendConfig field0)? piper,
    required TResult orElse(),
  }) {
    if (piper != null) {
      return piper(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(EngineBackend_Auto value) auto,
    required TResult Function(EngineBackend_Piper value) piper,
  }) {
    return piper(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(EngineBackend_Auto value)? auto,
    TResult? Function(EngineBackend_Piper value)? piper,
  }) {
    return piper?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(EngineBackend_Auto value)? auto,
    TResult Function(EngineBackend_Piper value)? piper,
    required TResult orElse(),
  }) {
    if (piper != null) {
      return piper(this);
    }
    return orElse();
  }
}

abstract class EngineBackend_Piper extends EngineBackend {
  const factory EngineBackend_Piper(final PiperBackendConfig field0) =
      _$EngineBackend_PiperImpl;
  const EngineBackend_Piper._() : super._();

  PiperBackendConfig get field0;

  /// Create a copy of EngineBackend
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EngineBackend_PiperImplCopyWith<_$EngineBackend_PiperImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
