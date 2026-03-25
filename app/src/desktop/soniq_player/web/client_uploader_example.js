// Przykład implementacji klienta WebSocket do przesyłania plików
// Kompatybilny z JavaScript/TypeScript w przeglądarce lub Node.js

/**
 * Klasa do obsługi uploadów plików przez WebSocket
 */
class SoniqFileUploader {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.ws = null;
    this.messageHandlers = new Map();
    this.connect();
  }

  connect() {
    this.ws = new WebSocket(this.wsUrl);
    this.ws.addEventListener('message', (event) => this.handleMessage(event));
    this.ws.addEventListener('error', (event) => console.error('WebSocket error:', event));
  }

  handleMessage(event) {
    try {
      const msg = JSON.parse(event.data);
      const sessionId = msg.sessionId;

      // Jeśli mamy handler dla tej sesji, wyślij mu wiadomość
      if (sessionId && this.messageHandlers.has(sessionId)) {
        const handler = this.messageHandlers.get(sessionId);
        handler(msg);
      }
    } catch (e) {
      console.error('Error parsing WebSocket message:', e);
    }
  }

  /**
   * Przesyłaj plik do serwera Soniq
   * @param {File} file - Plik do przesłania (z HTML5 File API)
   * @param {string} targetDir - Katalog docelowy ('Music' lub 'Muzyka')
   * @param {function} onProgress - Callback do raportowania postępu: (percentDone, bytesWritten) => void
   * @returns {Promise<object>} - Wynik uploadu: {filename, path}
   */
  async uploadFile(file, targetDir = 'Music', onProgress = null) {
    return new Promise((resolve, reject) => {
      // 1. Inicjalizuj upload
      const initMessage = {
        type: 'uploadFileStart',
        filename: file.name,
        totalSizeBytes: file.size,
        targetDir: targetDir
      };

      this.ws.send(JSON.stringify(initMessage));

      // Czekaj na uploadStart lub uploadError
      const sessionHandler = (msg) => {
        if (msg.type === 'uploadStart') {
          // Mamy sessionId, zaczynamy przesyłać chunki
          this.uploadChunks(file, msg.sessionId, onProgress)
            .then(resolve)
            .catch(reject);
        } else if (msg.type === 'uploadError') {
          reject(new Error(`Upload initialization failed: ${msg.error}`));
        }
      };

      // Tymczasowo obsłuż tę sesję aż do startUpload
      const tempHandler = (msg) => {
        if (msg.type === 'uploadStart' || msg.type === 'uploadError') {
          this.messageHandlers.delete('__init__');
          sessionHandler(msg);
        }
      };

      this.messageHandlers.set('__init__', tempHandler);

      // Timeout dla inicjalizacji
      setTimeout(() => {
        this.messageHandlers.delete('__init__');
        reject(new Error('Upload initialization timeout'));
      }, 10000);
    });
  }

  /**
   * Przesyłaj chunki pliku
   * @private
   */
  async uploadChunks(file, sessionId, onProgress) {
    return new Promise((resolve, reject) => {
      const chunkSize = 64 * 1024; // 64 KB na raz
      let offset = 0;

      const uploadNextChunk = async () => {
        if (offset >= file.size) {
          // Wszystkie chunki wysłane, finalizuj
          this.finalizUpload(sessionId)
            .then(resolve)
            .catch(reject);
          return;
        }

        const chunk = file.slice(offset, Math.min(offset + chunkSize, file.size));
        const buffer = await chunk.arrayBuffer();
        const base64 = this.arrayBufferToBase64(buffer);

        const chunkMessage = {
          type: 'uploadFileChunk',
          sessionId: sessionId,
          chunk: base64
        };

        this.ws.send(JSON.stringify(chunkMessage));

        offset += chunkSize;

        // Czekaj na potwierdzenie postępu
        const progressHandler = (msg) => {
          if (msg.type === 'uploadProgress' && msg.sessionId === sessionId) {
            if (onProgress) {
              onProgress(msg.percentDone, msg.bytesWritten);
            }
            uploadNextChunk();
          } else if (msg.type === 'uploadError' && msg.sessionId === sessionId) {
            this.messageHandlers.delete(sessionId);
            reject(new Error(`Upload chunk failed: ${msg.error}`));
          }
        };

        this.messageHandlers.set(sessionId, progressHandler);

        // Timeout dla chunka
        setTimeout(() => {
          if (this.messageHandlers.has(sessionId)) {
            this.messageHandlers.delete(sessionId);
            reject(new Error('Upload chunk timeout'));
          }
        }, 30000);
      };

      uploadNextChunk();
    });
  }

  /**
   * Finalizuj upload
   * @private
   */
  finalizUpload(sessionId) {
    return new Promise((resolve, reject) => {
      const finalizeMessage = {
        type: 'uploadFileEnd',
        sessionId: sessionId
      };

      this.ws.send(JSON.stringify(finalizeMessage));

      const finalizeHandler = (msg) => {
        this.messageHandlers.delete(sessionId);

        if (msg.type === 'uploadComplete' && msg.sessionId === sessionId) {
          resolve({
            filename: msg.filename,
            path: msg.path
          });
        } else if (msg.type === 'uploadError' && msg.sessionId === sessionId) {
          reject(new Error(`Upload finalization failed: ${msg.error}`));
        }
      };

      this.messageHandlers.set(sessionId, finalizeHandler);

      // Timeout dla finalizacji
      setTimeout(() => {
        if (this.messageHandlers.has(sessionId)) {
          this.messageHandlers.delete(sessionId);
          reject(new Error('Upload finalization timeout'));
        }
      }, 10000);
    });
  }

  /**
   * Konwertuj ArrayBuffer na base64
   * @private
   */
  arrayBufferToBase64(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  /**
   * Anuluj istniejący upload
   */
  cancelUpload(sessionId) {
    const cancelMessage = {
      type: 'uploadCancel',
      sessionId: sessionId
    };

    this.ws.send(JSON.stringify(cancelMessage));
    this.messageHandlers.delete(sessionId);
  }
}

// ============================================================================
// PRZYKŁAD UŻYCIA
// ============================================================================

/*
const uploader = new SoniqFileUploader('ws://localhost:8787/ws?token=YOUR_TOKEN');

// Obsługuj input file
document.getElementById('fileInput').addEventListener('change', async (event) => {
  const file = event.target.files[0];
  if (!file) return;

  try {
    const result = await uploader.uploadFile(file, 'Music', (percentDone, bytesWritten) => {
      console.log(`Upload progress: ${percentDone}%`);
      document.getElementById('progressBar').value = percentDone;
    });

    console.log('Upload complete:', result);
    alert(`File uploaded: ${result.filename}`);
  } catch (error) {
    console.error('Upload failed:', error);
    alert(`Upload failed: ${error.message}`);
  }
});
*/

// ============================================================================
// KLIENT CURL EXAMPLE (dla testowania)
// ============================================================================

/*
# 1. Inicjalizuj upload
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Origin: http://localhost:8787" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
  "ws://localhost:8787/ws?token=YOUR_TOKEN"

# Następnie wyślij (przez WebSocket):
# {"type":"uploadFileStart","filename":"test.mp3","totalSizeBytes":1024,"targetDir":"Music"}

# Odpowiedź:
# {"type":"uploadStart","sessionId":"abc123..."}

# 2. Przesyłaj chunki
# {"type":"uploadFileChunk","sessionId":"abc123...","chunk":"base64encodeddata=="}

# 3. Finalizuj
# {"type":"uploadFileEnd","sessionId":"abc123..."}
*/

// ============================================================================
// PYTHON EXAMPLE (dla testowania)
// ============================================================================

/*
import asyncio
import websockets
import json
import base64

async def upload_file_to_soniq(ws_url, file_path, target_dir='Music'):
    uri = ws_url

    async with websockets.connect(uri) as websocket:
        # 1. Inicjalizuj
        with open(file_path, 'rb') as f:
            file_size = len(f.read())

        init_msg = {
            'type': 'uploadFileStart',
            'filename': file_path.split('/')[-1],
            'totalSizeBytes': file_size,
            'targetDir': target_dir
        }

        await websocket.send(json.dumps(init_msg))
        response = await websocket.recv()
        init_response = json.loads(response)

        if init_response.get('type') != 'uploadStart':
            print(f"Error: {init_response}")
            return

        session_id = init_response['sessionId']
        print(f"Session ID: {session_id}")

        # 2. Przesyłaj chunki
        chunk_size = 64 * 1024
        with open(file_path, 'rb') as f:
            while True:
                chunk = f.read(chunk_size)
                if not chunk:
                    break

                chunk_msg = {
                    'type': 'uploadFileChunk',
                    'sessionId': session_id,
                    'chunk': base64.b64encode(chunk).decode('utf-8')
                }

                await websocket.send(json.dumps(chunk_msg))
                response = await websocket.recv()
                progress = json.loads(response)
                print(f"Progress: {progress.get('percentDone')}%")

        # 3. Finalizuj
        finalize_msg = {
            'type': 'uploadFileEnd',
            'sessionId': session_id
        }

        await websocket.send(json.dumps(finalize_msg))
        response = await websocket.recv()
        final_response = json.loads(response)

        if final_response.get('type') == 'uploadComplete':
            print(f"Upload complete: {final_response['filename']}")
        else:
            print(f"Error: {final_response}")

# Użycie:
# asyncio.run(upload_file_to_soniq('ws://localhost:8787/ws?token=YOUR_TOKEN', '/path/to/file.mp3'))
*/

