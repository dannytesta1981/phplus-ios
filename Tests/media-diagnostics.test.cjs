const vm = require('node:vm');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const script = fs.readFileSync('PrivateHub/media-diagnostics.js', 'utf8');
function fixture({media, secure=true, policy=true}={}) {
  const events=[], listeners={};
  const window = {isSecureContext:secure, webkit:{messageHandlers:{phplusMedia:{postMessage:m=>events.push(m)}}}, addEventListener:(n,f)=>listeners[n]=f};
  const navigator = media ? {mediaDevices:media} : {};
  const document = {addEventListener:()=>{}, featurePolicy:{allowsFeature:()=>policy}};
  vm.runInNewContext(script,{window,navigator,document,Reflect,Set});
  return {events,listeners,navigator};
}
(async()=>{
  let f=fixture(); assert(f.events.some(e=>e.code==='unavailable'));
  f=fixture({secure:false,policy:false}); assert(f.events.some(e=>e.code==='insecure')); assert(f.events.some(e=>e.code==='policyCameraDenied'));
  const stream={getTracks:()=>[]}; const constraints={video:{deviceId:'PRIVATE_DEVICE'},audio:false}; let received, receiver;
  const media={getUserMedia:function(c){received=c;receiver=this;return Promise.resolve(stream)}};
  f=fixture({media}); assert.equal(await f.navigator.mediaDevices.getUserMedia(constraints),stream);assert.equal(received,constraints);assert.equal(receiver,media);assert(f.events.some(e=>e.code==='success'));
  for (const name of ['NotAllowedError','SecurityError','NotFoundError','NotReadableError','OverconstrainedError','AbortError','TypeError','Unknown']) {
    const error={name,message:'PRIVATE_ERROR'};const x=fixture({media:{getUserMedia:()=>Promise.reject(error)}});
    await assert.rejects(x.navigator.mediaDevices.getUserMedia({video:true}),e=>e===error);
    assert(x.events.some(e=>e.code===(name==='Unknown'?'otherMediaError':name)));
    assert(!JSON.stringify(x.events).includes('PRIVATE_ERROR'));
  }
  f.listeners.error({message:'PRIVATE_PAGE'});f.listeners.unhandledrejection({reason:'PRIVATE_REASON'});
  assert(f.events.some(e=>e.code==='jsError'));assert(f.events.some(e=>e.code==='promiseError'));
  assert(!JSON.stringify(f.events).includes('PRIVATE_')); assert(f.events.every(e=>Object.keys(e).join(',')==='code'));
  const fixed={};Object.defineProperty(fixed,'getUserMedia',{value:()=>Promise.resolve(stream),writable:false});
  f=fixture({media:fixed});assert(f.events.some(e=>e.code==='instrumentationUnavailable'));
  console.log('Media diagnostics: API/context/policy, stream/error preservation, 8 error categories, privacy and frozen API checks passed. No camera/iPhone runtime test.');
})().catch(e=>{console.error(e);process.exit(1)});
