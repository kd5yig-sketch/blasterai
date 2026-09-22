// Minimal ZIP writer (STORE method — no compression). Good enough for an
// .obz export: the payload is already-compressed PNGs and small JSON, so
// deflate would buy little, and this keeps the app dependency-free.
//
// Entries are written flat, in the order given — required for OBZ, whose
// readers resolve `load_board.path` against the archive's own entry keys
// (docs/obf-interop.md: "the archive must be flat").

function crc32Table() {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
}
const CRC_TABLE = crc32Table();

function crc32(bytes) {
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    crc = CRC_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function dosDateTime() {
  // A fixed, reasonable timestamp — exported content has no meaningful
  // mtime, and every OBF reader ignores it.
  return { time: 0, date: 0x21 }; // 1980-01-01
}

function writeUint16(view, offset, value) {
  view.setUint16(offset, value, true);
}
function writeUint32(view, offset, value) {
  view.setUint32(offset, value, true);
}

// entries: [{ path: string, data: Uint8Array }]
// Returns a Blob of the assembled .zip/.obz.
export function zipStore(entries) {
  const encoder = new TextEncoder();
  const chunks = [];
  const centralRecords = [];
  let offset = 0;
  const { time, date } = dosDateTime();

  for (const { path, data } of entries) {
    const nameBytes = encoder.encode(path);
    const crc = crc32(data);
    const size = data.length;

    const localHeader = new ArrayBuffer(30);
    const lv = new DataView(localHeader);
    writeUint32(lv, 0, 0x04034b50);
    writeUint16(lv, 4, 20); // version needed
    writeUint16(lv, 6, 0); // flags
    writeUint16(lv, 8, 0); // method: STORE
    writeUint16(lv, 10, time);
    writeUint16(lv, 12, date);
    writeUint32(lv, 14, crc);
    writeUint32(lv, 18, size); // compressed size
    writeUint32(lv, 22, size); // uncompressed size
    writeUint16(lv, 26, nameBytes.length);
    writeUint16(lv, 28, 0); // extra length

    chunks.push(new Uint8Array(localHeader), nameBytes, data);

    centralRecords.push({ nameBytes, crc, size, offset });
    offset += 30 + nameBytes.length + size;
  }

  const centralStart = offset;
  for (const rec of centralRecords) {
    const central = new ArrayBuffer(46);
    const cv = new DataView(central);
    writeUint32(cv, 0, 0x02014b50);
    writeUint16(cv, 4, 20); // version made by
    writeUint16(cv, 6, 20); // version needed
    writeUint16(cv, 8, 0); // flags
    writeUint16(cv, 10, 0); // method
    writeUint16(cv, 12, time);
    writeUint16(cv, 14, date);
    writeUint32(cv, 16, rec.crc);
    writeUint32(cv, 20, rec.size);
    writeUint32(cv, 24, rec.size);
    writeUint16(cv, 28, rec.nameBytes.length);
    writeUint16(cv, 30, 0); // extra length
    writeUint16(cv, 32, 0); // comment length
    writeUint16(cv, 34, 0); // disk number start
    writeUint16(cv, 36, 0); // internal attrs
    writeUint32(cv, 38, 0); // external attrs
    writeUint32(cv, 42, rec.offset);
    chunks.push(new Uint8Array(central), rec.nameBytes);
    offset += 46 + rec.nameBytes.length;
  }
  const centralSize = offset - centralStart;

  const end = new ArrayBuffer(22);
  const ev = new DataView(end);
  writeUint32(ev, 0, 0x06054b50);
  writeUint16(ev, 4, 0); // disk number
  writeUint16(ev, 6, 0); // central dir disk
  writeUint16(ev, 8, centralRecords.length);
  writeUint16(ev, 10, centralRecords.length);
  writeUint32(ev, 12, centralSize);
  writeUint32(ev, 16, centralStart);
  writeUint16(ev, 20, 0); // comment length
  chunks.push(new Uint8Array(end));

  return new Blob(chunks, { type: "application/zip" });
}
