const http = require('http');
const path = require('path');
const fs   = require('fs');
const { PNG } = require('pngjs');

const PORT       = 3959;
const RESOURCE   = GetCurrentResourceName();
const RES_PATH   = GetResourcePath(RESOURCE);
const OUTPUT_DIR = path.join(RES_PATH, 'shots');

try {
    if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });
} catch (err) {
    console.log('^1[uz_AutoShot]^0 Output dir error: ' + err.message);
}

let manifestCache = null;
function buildItems() {
    const items = [];
    if (!fs.existsSync(OUTPUT_DIR)) return items;

    function walkDir(dir, rel) {
        let entries;
        try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
        for (const entry of entries) {
            const entryRel = rel ? rel + '/' + entry.name : entry.name;
            if (entry.isDirectory()) {
                walkDir(path.join(dir, entry.name), entryRel);
            } else if (/\.(png|webp|jpg)$/.test(entry.name)) {
                const parts = entryRel.replace(/\.(png|webp|jpg)$/, '').split('/');
                if (parts.length >= 3) {
                    const gender    = parts[0];
                    const catPart   = parts[1];
                    const drawPart  = parts[2];
                    const isProp    = catPart.startsWith('prop_');
                    const catId     = isProp ? parseInt(catPart.replace('prop_', '')) : parseInt(catPart);
                    const drawParts = drawPart.split('_');
                    items.push({
                        url:      'http://127.0.0.1:' + PORT + '/shots/' + entryRel,
                        file:     entryRel,
                        gender:   gender,
                        type:     isProp ? 'prop' : 'component',
                        id:       catId || 0,
                        drawable: parseInt(drawParts[0]) || 0,
                        texture:  parseInt(drawParts[1]) || 0,
                    });
                }
            }
        }
    }

    walkDir(OUTPUT_DIR, '');
    return items;
}

function getManifest() {
    if (!manifestCache) {
        const items = buildItems();
        manifestCache = { generatedAt: Date.now(), total: items.length, items };
    }
    return manifestCache;
}

function parseMultipart(body, boundary) {
    const boundaryBuf = Buffer.from('--' + boundary);
    const crlf        = Buffer.from('\r\n');
    const headerEnd   = Buffer.from('\r\n\r\n');

    // Find boundary positions
    let start = indexOf(body, boundaryBuf, 0);
    if (start === -1) return null;

    // Skip header after first boundary
    const headStart = start + boundaryBuf.length + crlf.length;
    const headEnd   = indexOf(body, headerEnd, headStart);
    if (headEnd === -1) return null;

    // File data start
    const dataStart = headEnd + headerEnd.length;

    // Find next boundary -> file data end
    const nextBoundary = indexOf(body, boundaryBuf, dataStart);
    if (nextBoundary === -1) return null;

    // Strip trailing \r\n
    const dataEnd = nextBoundary - crlf.length;

    // Try to extract filename from header
    const headerStr = body.slice(headStart, headEnd).toString('utf-8');
    let filename = 'upload';
    const fnMatch = headerStr.match(/filename="([^"]+)"/);
    if (fnMatch) filename = fnMatch[1];

    return {
        data: body.slice(dataStart, dataEnd),
        filename,
    };
}

function indexOf(buf, pattern, offset) {
    for (let i = offset; i <= buf.length - pattern.length; i++) {
        let found = true;
        for (let j = 0; j < pattern.length; j++) {
            if (buf[i + j] !== pattern[j]) {
                found = false;
                break;
            }
        }
        if (found) return i;
    }
    return -1;
}

function removeChromaKey(pngBuffer, mode) {
    const png = PNG.sync.read(pngBuffer);
    const d = png.data;
    const w = png.width, h = png.height;
    let removed = 0;
    const isMagenta = mode === 'magenta';

    for (let i = 0; i < d.length; i += 4) {
        const r = d[i], g = d[i + 1], b = d[i + 2];
        let keyness = 0;

        if (isMagenta) {
            const rOverG = r - g;
            const bOverG = b - g;
            const minOver = rOverG < bOverG ? rOverG : bOverG;
            const primary = r < b ? r : b;
            if (minOver > 0 && primary > 10) {
                // Soft edge: gradual ramp from 0-20 dominance range
                const edgeSoft = minOver < 20 ? minOver / 20 : 1;
                const primarySoft = primary < 40 ? (primary - 10) / 30 : 1;
                keyness = Math.min(1, (rOverG + bOverG) / (r + b + 1)) * edgeSoft * primarySoft;
            }
        } else {
            const gOverR = g - r;
            const gOverB = g - b;
            const minOver = gOverR < gOverB ? gOverR : gOverB;
            if (minOver > 0 && g > 10) {
                const edgeSoft = minOver < 20 ? minOver / 20 : 1;
                const primarySoft = g < 40 ? (g - 10) / 30 : 1;
                keyness = Math.min(1, (gOverR + gOverB) / (g + 1)) * edgeSoft * primarySoft;
            }
        }

        if (keyness > 0) {
            d[i + 3] = (255 * (1 - keyness) + 0.5) | 0;
            // Despill: remove chroma color bleed from RGB
            if (isMagenta) {
                d[i]     = (r - (r - g) * keyness + 0.5) | 0; // pull R toward G
                d[i + 2] = (b - (b - g) * keyness + 0.5) | 0; // pull B toward G
            } else {
                const cap = r > b ? r : b;
                d[i + 1] = (g - (g - cap) * keyness + 0.5) | 0; // pull G toward max(R,B)
            }
            removed++;
        }
    }

    // Two-pass alpha feather: 5x5 box blur on alpha channel for smooth edges
    const RADIUS = 2;
    const KERNEL = (RADIUS * 2 + 1) * (RADIUS * 2 + 1);
    const totalPx = w * h;
    const src = new Uint8Array(totalPx);

    for (let pass = 0; pass < 2; pass++) {
        for (let i = 0; i < totalPx; i++) src[i] = d[(i << 2) + 3];

        for (let y = RADIUS; y < h - RADIUS; y++) {
            for (let x = RADIUS; x < w - RADIUS; x++) {
                const idx = y * w + x;
                const a = src[idx];
                // Skip interior pixels (all neighbors same alpha)
                if ((a === 0 || a === 255) &&
                    src[idx - 1] === a && src[idx + 1] === a &&
                    src[idx - w] === a && src[idx + w] === a) continue;

                let sum = 0;
                for (let ky = -RADIUS; ky <= RADIUS; ky++) {
                    const rowOff = (y + ky) * w + x;
                    for (let kx = -RADIUS; kx <= RADIUS; kx++) {
                        sum += src[rowOff + kx];
                    }
                }
                d[(idx << 2) + 3] = (sum / KERNEL + 0.5) | 0;
            }
        }
    }

    console.log('^2[uz_AutoShot]^0 Chroma key (' + mode + '): ' + removed + '/' + totalPx + ' pixels removed, edges feathered');
    return PNG.sync.write(png, { colorType: 6 });
}

function resizePNG(pngBuffer, targetW, targetH) {
    const src = PNG.sync.read(pngBuffer);
    if (src.width === targetW && src.height === targetH) return pngBuffer;

    // Center-crop to target aspect ratio first, then resize
    const srcAspect = src.width / src.height;
    const dstAspect = targetW / targetH;

    let cropX = 0, cropY = 0, cropW = src.width, cropH = src.height;
    if (srcAspect > dstAspect) {
        // Source is wider -> crop sides
        cropW = Math.round(src.height * dstAspect);
        cropX = Math.round((src.width - cropW) / 2);
    } else if (srcAspect < dstAspect) {
        // Source is taller -> crop top/bottom
        cropH = Math.round(src.width / dstAspect);
        cropY = Math.round((src.height - cropH) / 2);
    }

    const dst = new PNG({ width: targetW, height: targetH, fill: true });
    const sd = src.data, dd = dst.data;
    const sw = src.width;
    const xRatio = cropW / targetW;
    const yRatio = cropH / targetH;

    // Use area averaging for downscale (sharper), bilinear for upscale
    const isDownscale = cropW > targetW || cropH > targetH;

    if (isDownscale) {
        // Area averaging: each dst pixel = average of all overlapping src pixels
        for (let y = 0; y < targetH; y++) {
            const sy0 = cropY + y * yRatio;
            const sy1 = cropY + (y + 1) * yRatio;
            const iy0 = sy0 | 0;
            const iy1 = Math.min((sy1 | 0) + 1, cropY + cropH);

            for (let x = 0; x < targetW; x++) {
                const sx0 = cropX + x * xRatio;
                const sx1 = cropX + (x + 1) * xRatio;
                const ix0 = sx0 | 0;
                const ix1 = Math.min((sx1 | 0) + 1, cropX + cropW);

                let r = 0, g = 0, b = 0, a = 0, totalW = 0;

                for (let sy = iy0; sy < iy1; sy++) {
                    // Vertical weight: how much of this row overlaps the dst pixel
                    const wy = (sy < sy0 ? 1 - (sy0 - sy) : sy + 1 > sy1 ? sy1 - sy : 1);
                    const rowOff = sy * sw;

                    for (let sx = ix0; sx < ix1; sx++) {
                        // Horizontal weight: how much of this column overlaps
                        const wx = (sx < sx0 ? 1 - (sx0 - sx) : sx + 1 > sx1 ? sx1 - sx : 1);
                        const w = wx * wy;
                        const si = (rowOff + sx) << 2;
                        r += sd[si]     * w;
                        g += sd[si + 1] * w;
                        b += sd[si + 2] * w;
                        a += sd[si + 3] * w;
                        totalW += w;
                    }
                }

                const di = (y * targetW + x) << 2;
                const inv = 1 / totalW;
                dd[di]     = (r * inv + 0.5) | 0;
                dd[di + 1] = (g * inv + 0.5) | 0;
                dd[di + 2] = (b * inv + 0.5) | 0;
                dd[di + 3] = (a * inv + 0.5) | 0;
            }
        }
    } else {
        // Bilinear interpolation for upscale
        const maxCropX = cropX + cropW - 1;
        const maxCropY = cropY + cropH - 1;

        for (let y = 0; y < targetH; y++) {
            const srcY = cropY + y * yRatio;
            const y0 = srcY | 0;
            const y1 = y0 < maxCropY ? y0 + 1 : maxCropY;
            const yf = srcY - y0;
            const yf1 = 1 - yf;
            const rowA = y0 * sw;
            const rowB = y1 * sw;

            for (let x = 0; x < targetW; x++) {
                const srcX = cropX + x * xRatio;
                const x0 = srcX | 0;
                const x1 = x0 < maxCropX ? x0 + 1 : maxCropX;
                const xf = srcX - x0;
                const xf1 = 1 - xf;

                const i00 = (rowA + x0) << 2;
                const i10 = (rowA + x1) << 2;
                const i01 = (rowB + x0) << 2;
                const i11 = (rowB + x1) << 2;
                const di  = (y * targetW + x) << 2;

                const w00 = xf1 * yf1, w10 = xf * yf1, w01 = xf1 * yf, w11 = xf * yf;
                dd[di]     = (sd[i00]     * w00 + sd[i10]     * w10 + sd[i01]     * w01 + sd[i11]     * w11 + 0.5) | 0;
                dd[di + 1] = (sd[i00 + 1] * w00 + sd[i10 + 1] * w10 + sd[i01 + 1] * w01 + sd[i11 + 1] * w11 + 0.5) | 0;
                dd[di + 2] = (sd[i00 + 2] * w00 + sd[i10 + 2] * w10 + sd[i01 + 2] * w01 + sd[i11 + 2] * w11 + 0.5) | 0;
                dd[di + 3] = (sd[i00 + 3] * w00 + sd[i10 + 3] * w10 + sd[i01 + 3] * w01 + sd[i11 + 3] * w11 + 0.5) | 0;
            }
        }
    }

    // Light sharpen on RGB after downscale (3x3 unsharp: center 5, neighbors -1)
    if (isDownscale) {
        const STRENGTH = 0.3;
        for (let y = 1; y < targetH - 1; y++) {
            for (let x = 1; x < targetW - 1; x++) {
                const ci = (y * targetW + x) << 2;
                // Skip fully transparent pixels
                if (dd[ci + 3] === 0) continue;
                const t = (ci - (targetW << 2));     // top row
                const b = (ci + (targetW << 2));     // bottom row
                for (let c = 0; c < 3; c++) {
                    const sharp = 5 * dd[ci + c] - dd[t + c] - dd[b + c] - dd[ci - 4 + c] - dd[ci + 4 + c];
                    const blended = dd[ci + c] + (sharp - dd[ci + c]) * STRENGTH;
                    dd[ci + c] = blended < 0 ? 0 : blended > 255 ? 255 : (blended + 0.5) | 0;
                }
            }
        }
    }

    console.log('^2[uz_AutoShot]^0 Crop+Resize: ' + src.width + 'x' + src.height + ' -> ' + cropW + 'x' + cropH + ' -> ' + targetW + 'x' + targetH + (isDownscale ? ' (area avg + sharpen)' : ' (bilinear)'));
    return PNG.sync.write(dst, { colorType: 6 });
}

const server = http.createServer((req, res) => {
    // CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', '*');

    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    if (req.method === 'GET' && req.url.startsWith('/api/')) {
        const rawPath  = req.url.split('?')[0];
        const queryStr = req.url.includes('?') ? req.url.split('?')[1] : '';
        const params   = {};
        queryStr.split('&').forEach(p => {
            const idx = p.indexOf('=');
            if (idx > 0) params[decodeURIComponent(p.slice(0, idx))] = decodeURIComponent(p.slice(idx + 1));
        });

        const parts = rawPath.slice(5).split('/').filter(Boolean);
        const route = parts[0];

        res.setHeader('Content-Type', 'application/json');

        if (route === 'stats') {
            const manifest = getManifest();
            const byGender = {}, byType = {};
            for (const item of manifest.items) {
                byGender[item.gender] = (byGender[item.gender] || 0) + 1;
                byType[item.type]     = (byType[item.type]     || 0) + 1;
            }
            res.writeHead(200);
            res.end(JSON.stringify({ total: manifest.total, byGender, byType }));
            return;
        }

        if (route === 'exists') {
            const { gender, type, id, drawable, texture } = params;
            const prefix = type === 'prop' ? 'prop_' : '';
            const exts   = ['.png', '.webp', '.jpg'];
            let found    = false;
            for (const e of exts) {
                const fp = path.join(OUTPUT_DIR, gender, prefix + id, drawable + '_' + texture + e);
                if (fs.existsSync(fp)) { found = true; break; }
            }
            res.writeHead(200);
            res.end(JSON.stringify({ exists: found }));
            return;
        }

        if (route === 'manifest') {
            let items         = getManifest().items;
            const filterGender = parts[1] || null;
            const filterType   = parts[2] || null;
            const filterId     = parts[3] !== undefined ? parseInt(parts[3]) : undefined;

            if (filterGender)           items = items.filter(i => i.gender === filterGender);
            if (filterType)             items = items.filter(i => i.type === filterType);
            if (filterId !== undefined) items = items.filter(i => i.id === filterId);

            res.writeHead(200);
            res.end(JSON.stringify({ generatedAt: getManifest().generatedAt, total: items.length, items }));
            return;
        }

        res.writeHead(404);
        res.end(JSON.stringify({ error: 'Unknown API route' }));
        return;
    }

    if (req.method === 'GET' && req.url.startsWith('/shots/')) {
        const relPath = decodeURIComponent(req.url.split('?')[0].replace('/shots/', ''));
        const filePath = path.join(OUTPUT_DIR, relPath);

        if (!filePath.startsWith(OUTPUT_DIR)) {
            res.writeHead(403);
            res.end();
            return;
        }

        if (!fs.existsSync(filePath)) {
            res.writeHead(404);
            res.end();
            return;
        }

        const ext = path.extname(filePath).toLowerCase();
        const mimeMap = { '.png': 'image/png', '.webp': 'image/webp', '.jpg': 'image/jpeg' };
        const mime = mimeMap[ext] || 'application/octet-stream';

        res.writeHead(200, {
            'Content-Type': mime,
            'Cache-Control': 'no-cache, no-store, must-revalidate',
        });
        res.end(fs.readFileSync(filePath));
        return;
    }

    if (req.method === 'POST' && req.url === '/upload') {
        const chunks = [];
        let totalSize = 0;
        const MAX_SIZE = 15 * 1024 * 1024;

        req.on('data', (chunk) => {
            totalSize += chunk.length;
            if (totalSize > MAX_SIZE) {
                res.writeHead(413, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'File too large' }));
                req.destroy();
                return;
            }
            chunks.push(chunk);
        });

        req.on('end', () => {
            try {
                const body = Buffer.concat(chunks);

                const contentType = req.headers['content-type'] || '';
                const boundaryMatch = contentType.match(/boundary=(.+)/);

                if (!boundaryMatch) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'No boundary found' }));
                    return;
                }

                const boundary = boundaryMatch[1].trim();
                const parsed = parseMultipart(body, boundary);

                if (!parsed || !parsed.data || parsed.data.length === 0) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'No file data parsed' }));
                    return;
                }

                const xFilename    = req.headers['x-filename'] || 'unknown';
                const wantFormat   = req.headers['x-format'] || 'png';
                const wantTransp   = req.headers['x-transparent'] === '1';
                const chromaKey    = req.headers['x-chromakey'] || 'green';
                const wantWidth    = parseInt(req.headers['x-width'])  || 0;
                const wantHeight   = parseInt(req.headers['x-height']) || 0;

                let outputData = parsed.data;
                let ext = wantFormat;

                if (wantTransp) {
                    try {
                        outputData = removeChromaKey(parsed.data, chromaKey);
                        ext = 'png';
                    } catch (e) {
                        console.log('^3[uz_AutoShot]^0 Chroma key skipped: ' + e.message);
                    }
                }

                if (wantWidth > 0 && wantHeight > 0 && ext === 'png') {
                    const MAX_DIM = 4096;
                    const clampedW = Math.min(Math.max(wantWidth, 16), MAX_DIM);
                    const clampedH = Math.min(Math.max(wantHeight, 16), MAX_DIM);
                    try {
                        outputData = resizePNG(outputData, clampedW, clampedH);
                    } catch (e) {
                        console.log('^3[uz_AutoShot]^0 Resize skipped: ' + e.message);
                    }
                } else if (wantWidth > 0 && wantHeight > 0 && ext !== 'png') {
                    console.log('^3[uz_AutoShot]^0 Resize requires PNG format; skipping for ' + ext);
                }

                const outputPath = path.join(OUTPUT_DIR, xFilename + '.' + ext);
                const dir = path.dirname(outputPath);
                if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
                fs.writeFileSync(outputPath, outputData);
                manifestCache = null;

                const sizeKB = Math.round(outputData.length / 1024);
                const label = wantTransp ? 'bg removed' : ext;
                console.log('^2[uz_AutoShot]^0 Saved: ' + xFilename + '.' + ext + ' (' + sizeKB + ' KB, ' + label + ')');

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, filename: xFilename + '.' + ext }));
            } catch (err) {
                console.log('^1[uz_AutoShot]^0 Process error: ' + err.message);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: err.message }));
            }
        });

        req.on('error', (err) => {
            console.log('^1[uz_AutoShot]^0 Request error: ' + err.message);
        });

        return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
});

server.on('error', (err) => {
    console.log('^1[uz_AutoShot]^0 Server error: ' + err.message);
});

server.listen(PORT, '127.0.0.1', () => {
    console.log('^2[uz_AutoShot]^0 Backend ready on http://127.0.0.1:' + PORT);
});

onNet('uz_autoshot:server:setBucket', (bucket) => {
    const src = source;
    SetPlayerRoutingBucket(src.toString(), bucket);
    console.log('^2[uz_AutoShot]^0 Player ' + src + ' -> bucket ' + bucket);
});

onNet('uz_autoshot:server:resetBucket', () => {
    const src = source;
    SetPlayerRoutingBucket(src.toString(), 0);
    console.log('^2[uz_AutoShot]^0 Player ' + src + ' -> bucket 0');
});

onNet('uz_autoshot:server:getClothingData', () => {
    const src = source;
    try {
        emitNet('uz_autoshot:client:receiveClothingData', src, getManifest().items);
    } catch (err) {
        console.log('^1[uz_AutoShot]^0 List error: ' + err.message);
        emitNet('uz_autoshot:client:receiveClothingData', src, []);
    }
});

on('uz_autoshot:getManifest', (gender) => {
    try {
        let items = getManifest().items;
        if (gender) items = items.filter(i => i.gender === gender);
        emit('uz_autoshot:manifestResult', { total: items.length, items });
    } catch (err) {
        emit('uz_autoshot:manifestResult', { total: 0, items: [] });
    }
});

