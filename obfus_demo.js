'use strict';

function obfuscateInstructionData(buf) {
  const HUMIDIFI_IX_DATA_KEY = 0xC3EBBAE2FF2FFF3An; // BigInt 64-bit key
  const POS_INC = 0x0001000100010001n;
  const chunk = 8;
  let posMask = 0n;

  const fullLen = Math.floor(buf.length / chunk) * chunk;

  for (let i = 0; i < fullLen; i += chunk) {
    const qword = buf.readBigUInt64LE(i);
    let enc = qword ^ HUMIDIFI_IX_DATA_KEY;
    enc ^= posMask;
    buf.writeBigUInt64LE(enc, i);
    posMask = (posMask + POS_INC) & 0xFFFFFFFFFFFFFFFFn;
  }

  const remLen = buf.length - fullLen;
  if (remLen > 0) {
    const tmp = Buffer.alloc(8, 0);
    buf.copy(tmp, 0, fullLen, fullLen + remLen);
    let rem = tmp.readBigUInt64LE(0);
    rem ^= HUMIDIFI_IX_DATA_KEY;
    rem ^= posMask;
    tmp.writeBigUInt64LE(rem, 0);
    tmp.copy(buf, fullLen, 0, remLen);
  }
}

function main() {
  const data = Buffer.from(Array.from({ length: 17 }, (_, i) => i + 1)); // 1..17
  console.log('before:', data.toString('hex'));
  obfuscateInstructionData(data);
  console.log('after :', data.toString('hex'));
  obfuscateInstructionData(data);
  console.log('again :', data.toString('hex'));
}

if (require.main === module) {
  main();
}

