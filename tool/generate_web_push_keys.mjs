import { generateKeyPairSync } from 'node:crypto';

const { publicKey, privateKey } = generateKeyPairSync('ec', {
  namedCurve: 'prime256v1',
});
const publicJwk = publicKey.export({ format: 'jwk' });
const privateJwk = privateKey.export({ format: 'jwk' });
publicJwk.ext = true;
publicJwk.key_ops = ['verify'];
privateJwk.ext = true;
privateJwk.key_ops = ['sign'];

function fromBase64Url(value) {
  return Buffer.from(value, 'base64url');
}

const applicationServerKey = Buffer.concat([
  Buffer.from([0x04]),
  fromBase64Url(publicJwk.x),
  fromBase64Url(publicJwk.y),
]).toString('base64url');

const exportedKeys = JSON.stringify({
  publicKey: publicJwk,
  privateKey: privateJwk,
});

console.log('WEB_PUSH_VAPID_PUBLIC_KEY');
console.log(applicationServerKey);
console.log('');
console.log('GAHUNDA_VAPID_KEYS_JSON');
console.log(exportedKeys);
console.log('');
console.log('Keep GAHUNDA_VAPID_KEYS_JSON private. Never commit it to GitHub.');
