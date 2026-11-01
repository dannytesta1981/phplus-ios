(() => {
  'use strict';
  const emit = code => {
    try { window.webkit.messageHandlers.phplusMedia.postMessage({code}); } catch (_) {}
  };
  const known = new Set(['NotAllowedError','SecurityError','NotFoundError','NotReadableError','OverconstrainedError','AbortError','TypeError']);
  const reportContext = () => {
    emit(window.isSecureContext ? 'secure' : 'insecure');
    emit(navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function' ? 'available' : 'unavailable');
    const policy = document.permissionsPolicy || document.featurePolicy;
    if (!policy || typeof policy.allowsFeature !== 'function') { emit('policyUnknown'); return; }
    try {
      emit(policy.allowsFeature('camera') ? 'policyCameraAllowed' : 'policyCameraDenied');
      if (!policy.allowsFeature('microphone')) emit('policyMicDenied');
    } catch (_) { emit('policyUnknown'); }
  };
  reportContext();
  document.addEventListener('DOMContentLoaded', reportContext, {once: true});
  window.addEventListener('error', () => emit('jsError'));
  window.addEventListener('unhandledrejection', () => emit('promiseError'));
  const media = navigator.mediaDevices;
  if (!media || typeof media.getUserMedia !== 'function') return;
  const original = media.getUserMedia;
  try {
    media.getUserMedia = function(...args) {
      emit('request');
      let promise;
      try { promise = Reflect.apply(original, this, args); }
      catch (error) { emit(known.has(error && error.name) ? error.name : 'otherMediaError'); throw error; }
      return promise.then(stream => { emit('success'); return stream; }, error => {
        emit(known.has(error && error.name) ? error.name : 'otherMediaError');
        throw error;
      });
    };
  } catch (_) { emit('instrumentationUnavailable'); }
})();
