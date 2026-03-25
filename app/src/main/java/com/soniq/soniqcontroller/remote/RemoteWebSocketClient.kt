package com.soniq.soniqcontroller.remote

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import android.os.Handler
import android.os.Looper
import com.soniq.soniqcontroller.song.SongState
object RemoteWebSocketClient {

    private var webSocket: WebSocket? = null

    private var messageListener: ((String) -> Unit)? = null

    fun setOnMessageListener(listener: (String) -> Unit) {
        messageListener = listener
    }

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    var isConnected = false
        private set

    fun connect(
        ip: String,
        port: Int,
        token: String?,
        code: String?,
        onConnected: () -> Unit,
        onError: (String) -> Unit
    ) {

        val url = when {
            !token.isNullOrBlank() ->
                token
            !code.isNullOrBlank() ->
                "ws://$ip:$port/ws?code=$code"
            else -> {
                onError("Brak tokenu i kodu")
                return
            }
        }


        val request = Request.Builder()
            .url(url)
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {

            override fun onOpen(ws: WebSocket, response: Response) {
                isConnected = true
                Handler(Looper.getMainLooper()).post {
                    onConnected()
                }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                Handler(Looper.getMainLooper()).post {
                    messageListener?.invoke(text)
                }
            }

            override fun onClosing(ws: WebSocket, code: Int, reason: String) {
                isConnected = false
                ws.close(1000, null)
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                isConnected = false
                Handler(Looper.getMainLooper()).post {
                    onError(t.message ?: "Błąd połączenia")
                }
            }
        })
    }

    fun sendAction(action: String, value: Any? = null) {
        val json = JSONObject()
        json.put("action", action)
        if (value != null) {
            json.put("value", value)
        }
        webSocket?.send(json.toString())
    }

    fun send(json: String) {
        webSocket?.send(json)
    }

    fun disconnect() {
        webSocket?.close(1000, "Zamknięto")
        webSocket = null
        isConnected = false
    }
}