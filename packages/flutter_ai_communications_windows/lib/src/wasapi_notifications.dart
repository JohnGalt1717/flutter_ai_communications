import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// [IMMNotificationClient] that forwards endpoint add/remove/state/default
/// changes. Property-value churn is ignored.
///
/// Callbacks use [NativeCallable.isolateLocal] so HRESULT can be returned.
/// Registration must stay on the Flutter STA thread.
final class WasapiDeviceWatch {
  /// Creates a watch against [enumerator].
  WasapiDeviceWatch(this._enumerator, this._onChange);

  final IMMDeviceEnumerator _enumerator;
  final void Function() _onChange;

  Pointer<Pointer<IMMNotificationClientVtbl>>? _object;
  Pointer<IMMNotificationClientVtbl>? _vtbl;
  NativeCallable<
    Int32 Function(VTablePointer, Pointer<GUID>, Pointer<Pointer<NativeType>>)
  >?
  _queryInterface;
  NativeCallable<Uint32 Function(VTablePointer)>? _addRef;
  NativeCallable<Uint32 Function(VTablePointer)>? _release;
  NativeCallable<Int32 Function(VTablePointer, Pointer<Utf16>, Uint32)>?
  _onState;
  NativeCallable<Int32 Function(VTablePointer, Pointer<Utf16>)>? _onAdded;
  NativeCallable<Int32 Function(VTablePointer, Pointer<Utf16>)>? _onRemoved;
  NativeCallable<Int32 Function(VTablePointer, Int32, Int32, Pointer<Utf16>)>?
  _onDefault;
  NativeCallable<Int32 Function(VTablePointer, Pointer<Utf16>, PROPERTYKEY)>?
  _onProperty;
  var _refs = 1;
  var _registered = false;
  var _coalesced = false;

  /// Registers for MMDevice notifications.
  void start() {
    if (_registered) {
      return;
    }
    final vtbl = calloc<IMMNotificationClientVtbl>();
    final object = calloc<Pointer<IMMNotificationClientVtbl>>();
    object.value = vtbl;
    _vtbl = vtbl;
    _object = object;

    _queryInterface =
        NativeCallable<
          Int32 Function(
            VTablePointer,
            Pointer<GUID>,
            Pointer<Pointer<NativeType>>,
          )
        >.isolateLocal(_query, exceptionalReturn: 0);
    _addRef = NativeCallable<Uint32 Function(VTablePointer)>.isolateLocal(
      _add,
      exceptionalReturn: 0,
    );
    _release = NativeCallable<Uint32 Function(VTablePointer)>.isolateLocal(
      _drop,
      exceptionalReturn: 0,
    );
    _onState =
        NativeCallable<
          Int32 Function(VTablePointer, Pointer<Utf16>, Uint32)
        >.isolateLocal(_changed, exceptionalReturn: 0);
    _onAdded =
        NativeCallable<
          Int32 Function(VTablePointer, Pointer<Utf16>)
        >.isolateLocal(_changedId, exceptionalReturn: 0);
    _onRemoved =
        NativeCallable<
          Int32 Function(VTablePointer, Pointer<Utf16>)
        >.isolateLocal(_changedId, exceptionalReturn: 0);
    _onDefault =
        NativeCallable<
          Int32 Function(VTablePointer, Int32, Int32, Pointer<Utf16>)
        >.isolateLocal(_changedDefault, exceptionalReturn: 0);
    _onProperty =
        NativeCallable<
          Int32 Function(VTablePointer, Pointer<Utf16>, PROPERTYKEY)
        >.isolateLocal(_ignoreProperty, exceptionalReturn: 0);

    vtbl.ref
      ..base$.QueryInterface = _queryInterface!.nativeFunction
      ..base$.AddRef = _addRef!.nativeFunction
      ..base$.Release = _release!.nativeFunction
      ..OnDeviceStateChanged = _onState!.nativeFunction
      ..OnDeviceAdded = _onAdded!.nativeFunction
      ..OnDeviceRemoved = _onRemoved!.nativeFunction
      ..OnDefaultDeviceChanged = _onDefault!.nativeFunction
      ..OnPropertyValueChanged = _onProperty!.nativeFunction;

    final client = IMMNotificationClient(object.cast());
    try {
      _enumerator.registerEndpointNotificationCallback(client);
      _registered = true;
    } on Object {
      _teardown(unregister: false);
    }
  }

  /// Whether MMDevice registration succeeded.
  bool get isRegistered => _registered;

  /// Unregisters and frees the COM object.
  void stop() => _teardown(unregister: true);

  void _teardown({required bool unregister}) {
    final object = _object;
    if (unregister && _registered && object != null) {
      try {
        _enumerator.unregisterEndpointNotificationCallback(
          IMMNotificationClient(object.cast()),
        );
      } on Object {
        return;
      }
      _registered = false;
    }
    if (_registered) {
      return;
    }
    _queryInterface?.close();
    _addRef?.close();
    _release?.close();
    _onState?.close();
    _onAdded?.close();
    _onRemoved?.close();
    _onDefault?.close();
    _onProperty?.close();
    _queryInterface = null;
    _addRef = null;
    _release = null;
    _onState = null;
    _onAdded = null;
    _onRemoved = null;
    _onDefault = null;
    _onProperty = null;
    if (_vtbl != null) {
      calloc.free(_vtbl!);
      _vtbl = null;
    }
    if (_object != null) {
      calloc.free(_object!);
      _object = null;
    }
  }

  int _query(
    VTablePointer _,
    Pointer<GUID> iid,
    Pointer<Pointer<NativeType>> out,
  ) {
    if (_sameGuid(iid, IID_IUnknown) ||
        _sameGuid(iid, IID_IMMNotificationClient)) {
      out.value = _object!.cast();
      _refs++;
      return 0;
    }
    out.value = nullptr;
    return -2147467262;
  }

  int _add(VTablePointer _) {
    _refs++;
    return _refs;
  }

  int _drop(VTablePointer _) {
    _refs--;
    return _refs;
  }

  int _changed(VTablePointer _, Pointer<Utf16> __, int ___) {
    _signal();
    return 0;
  }

  int _changedId(VTablePointer _, Pointer<Utf16> __) {
    _signal();
    return 0;
  }

  int _changedDefault(VTablePointer _, int __, int ___, Pointer<Utf16> ____) {
    _signal();
    return 0;
  }

  int _ignoreProperty(VTablePointer _, Pointer<Utf16> __, PROPERTYKEY ___) {
    return 0;
  }

  void _signal() {
    if (_coalesced) {
      return;
    }
    _coalesced = true;
    Future<void>.microtask(() {
      _coalesced = false;
      _onChange();
    });
  }

  bool _sameGuid(Pointer<GUID> a, GUID b) {
    if (a.ref.Data1 != b.Data1 ||
        a.ref.Data2 != b.Data2 ||
        a.ref.Data3 != b.Data3) {
      return false;
    }
    for (var i = 0; i < 8; i++) {
      if (a.ref.Data4[i] != b.Data4[i]) {
        return false;
      }
    }
    return true;
  }
}
