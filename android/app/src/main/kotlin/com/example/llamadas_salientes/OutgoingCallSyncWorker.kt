package com.example.llamadas_salientes

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class OutgoingCallSyncWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {

    companion object {
        const val WORK_NAME = "outgoing_call_daily_sync"
        private const val DATABASE_NAME = "registro_llamadas_salientes.db"
        private const val CAPSULE_BASE = "https://api.capsulecrm.com/api/v2"

        // Lee la API key desde SharedPreferences (la guardamos desde Flutter)
        fun getApiKey(context: Context): String {
            val prefs = context.getSharedPreferences("capsule_prefs", Context.MODE_PRIVATE)
            return prefs.getString("api_key", "") ?: ""
        }
    }

    override fun doWork(): Result {
        android.util.Log.d("CAPSULE_WORKER", "🔵 doWork() iniciado")

        if (!hasRequiredPermissions()) {
            android.util.Log.d("CAPSULE_WORKER", "❌ Sin permisos")
            return Result.success()
        }

        android.util.Log.d("CAPSULE_WORKER", "✅ Permisos OK, iniciando sync...")


        if (!hasRequiredPermissions()) return Result.success()

        return try {
            val db = openDatabase()
            ensureSchema(db)

            val now = System.currentTimeMillis()
            val from = now - 48L * 60 * 60 * 1000L

            val excludedRules = getExcludedRules(db)
            syncOutgoingCalls(db, excludedRules, from, now)

            // Después de guardar en SQLite, sincroniza con Capsule
            val apiKey = getApiKey(applicationContext)
            if (apiKey.isNotEmpty()) {
                syncToCapsule(db, apiKey)
            }

            db.close()
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun syncToCapsule(db: android.database.sqlite.SQLiteDatabase, apiKey: String) {
        android.util.Log.d("CAPSULE_WORKER", "📤 syncToCapsule iniciado, apiKey vacía: ${apiKey.isEmpty()}")

        val cursor = db.query(
            "llamadas_salientes",
            null,
            "sincronizado = 0",
            null, null, null,
            "timestamp DESC"
        )

        cursor?.use {
            val idIdx = it.getColumnIndexOrThrow("id")
            val numIdx = it.getColumnIndexOrThrow("numero")
            val fechaIdx = it.getColumnIndexOrThrow("fecha")
            val horaIdx = it.getColumnIndexOrThrow("hora")
            val durIdx = it.getColumnIndexOrThrow("duracion")
            val estIdx = it.getColumnIndexOrThrow("estado")

            while (it.moveToNext()) {
                val callId = it.getInt(idIdx)
                val numero = it.getString(numIdx) ?: continue
                val fecha = it.getString(fechaIdx) ?: ""
                val hora = it.getString(horaIdx) ?: ""
                val duracion = it.getInt(durIdx)
                val estado = it.getString(estIdx) ?: ""

                if (numero.isBlank()) continue

                val partyId = findContactByPhone(numero, apiKey) ?: continue
                val opportunityId = findManualCallOpportunity(partyId, apiKey) ?: continue
                val ok = addCallToOpportunity(
                    opportunityId, numero, fecha, hora, duracion, estado, apiKey
                )

                if (ok) {
                    db.update(
                        "llamadas_salientes",
                        ContentValues().apply { put("sincronizado", 1) },
                        "id = ?",
                        arrayOf(callId.toString())
                    )
                }
            }
        }
    }

    private fun last10Digits(phone: String): String {
        val digits = phone.replace(Regex("[^0-9]"), "")
        return if (digits.length <= 10) digits else digits.substring(digits.length - 10)
    }

    private fun findContactByPhone(phoneNumber: String, apiKey: String): Int? {
        val clean = last10Digits(phoneNumber)
        val url = URL("$CAPSULE_BASE/parties/search?q=${clean}")
        val conn = url.openConnection() as HttpURLConnection
        conn.setRequestProperty("Authorization", "Bearer $apiKey")
        conn.setRequestProperty("Accept", "application/json")

        if (conn.responseCode != 200) return null

        val body = conn.inputStream.bufferedReader().readText()
        val parties = JSONObject(body).getJSONArray("parties")

        for (i in 0 until parties.length()) {
            val party = parties.getJSONObject(i)
            val phones = party.optJSONArray("phoneNumbers") ?: continue
            for (j in 0 until phones.length()) {
                val num = phones.getJSONObject(j).optString("number", "")
                if (last10Digits(num) == clean && clean.isNotEmpty()) {
                    return party.getInt("id")
                }
            }
        }
        return null
    }

    private fun findManualCallOpportunity(partyId: Int, apiKey: String): Int? {
        val url = URL("$CAPSULE_BASE/parties/$partyId/opportunities")
        val conn = url.openConnection() as HttpURLConnection
        conn.setRequestProperty("Authorization", "Bearer $apiKey")
        conn.setRequestProperty("Accept", "application/json")

        if (conn.responseCode != 200) return null

        val body = conn.inputStream.bufferedReader().readText()
        val opps = JSONObject(body).getJSONArray("opportunities")
        if (opps.length() == 0) return null
        return opps.getJSONObject(0).getInt("id")
    }

    private fun addCallToOpportunity(
        opportunityId: Int,
        phoneNumber: String,
        fecha: String,
        hora: String,
        duracion: Int,
        estado: String,
        apiKey: String
    ): Boolean {
        val durationText = if (duracion > 0)
            "${duracion / 60}m ${duracion % 60}s"
        else "No respondida"

        val payload = JSONObject().apply {
            put("entry", JSONObject().apply {
                put("type", "note")
                put("content", " Llamada saliente\n$phoneNumber\n $fecha   $hora\n Duración: $durationText\n Estado: $estado")
                put("opportunity", JSONObject().apply { put("id", opportunityId) })
            })
        }

        val url = URL("$CAPSULE_BASE/entries")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.setRequestProperty("Authorization", "Bearer $apiKey")
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setRequestProperty("Accept", "application/json")

        OutputStreamWriter(conn.outputStream).use { it.write(payload.toString()) }
        return conn.responseCode in 200..299
    }

    // ── Los métodos de abajo son los que ya tenías ──

    private fun hasRequiredPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(
            applicationContext, Manifest.permission.READ_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(
                    applicationContext, Manifest.permission.READ_CONTACTS
                ) == PackageManager.PERMISSION_GRANTED
    }

    private fun openDatabase(): android.database.sqlite.SQLiteDatabase {
        val dbFile = applicationContext.getDatabasePath(DATABASE_NAME)
        dbFile.parentFile?.mkdirs()
        return android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(dbFile, null)
    }

    private fun ensureSchema(db: android.database.sqlite.SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS llamadas_salientes (
                id INTEGER PRIMARY KEY,
                fecha DATE, hora TIME, numero TEXT,
                nombre_contacto TEXT, duracion INTEGER,
                estado TEXT, timestamp INTEGER,
                sincronizado INTEGER DEFAULT 0
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS numeros_excluidos (
                id INTEGER PRIMARY KEY, numero TEXT, tipo TEXT
            )
        """.trimIndent())

        db.execSQL("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_llamadas_timestamp_numero
            ON llamadas_salientes(timestamp, numero)
        """.trimIndent())

        // Migración: agrega columna sincronizado si no existe
        try {
            db.execSQL("ALTER TABLE llamadas_salientes ADD COLUMN sincronizado INTEGER DEFAULT 0")
        } catch (_: Exception) {}
    }

    private fun getExcludedRules(db: android.database.sqlite.SQLiteDatabase): List<Pair<String, String>> {
        val rules = mutableListOf<Pair<String, String>>()
        db.query("numeros_excluidos", arrayOf("numero", "tipo"), null, null, null, null, null)?.use {
            while (it.moveToNext()) {
                rules.add(Pair(it.getString(0) ?: "", it.getString(1) ?: ""))
            }
        }
        return rules
    }

    private fun syncOutgoingCalls(
        db: android.database.sqlite.SQLiteDatabase,
        excludedRules: List<Pair<String, String>>,
        fromTimestamp: Long,
        toTimestamp: Long
    ) {
        val cursor = applicationContext.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME,
                CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE),
            "${CallLog.Calls.TYPE} = ? AND ${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.DATE} <= ?",
            arrayOf(CallLog.Calls.OUTGOING_TYPE.toString(), fromTimestamp.toString(), toTimestamp.toString()),
            "${CallLog.Calls.DATE} DESC"
        ) ?: return

        val dateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val timeFormatter = SimpleDateFormat("HH:mm", Locale.US)

        cursor.use {
            val numIdx = it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
            val nameIdx = it.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)
            val dateIdx = it.getColumnIndexOrThrow(CallLog.Calls.DATE)
            val durIdx = it.getColumnIndexOrThrow(CallLog.Calls.DURATION)

            while (it.moveToNext()) {
                val number = it.getString(numIdx)?.trim() ?: continue
                if (number.isBlank() || isExcluded(number, excludedRules)) continue

                val timestamp = it.getLong(dateIdx)
                val duration = it.getInt(durIdx)
                val date = Date(timestamp)

                db.insertWithOnConflict(
                    "llamadas_salientes", null,
                    ContentValues().apply {
                        put("fecha", dateFormatter.format(date))
                        put("hora", timeFormatter.format(date))
                        put("numero", number)
                        put("nombre_contacto", it.getString(nameIdx) ?: "")
                        put("duracion", duration)
                        put("estado", if (duration > 0) "Respondida" else "No respondida")
                        put("timestamp", timestamp)
                        put("sincronizado", 0)
                    },
                    android.database.sqlite.SQLiteDatabase.CONFLICT_IGNORE
                )
            }
        }
    }

    private fun isExcluded(number: String, rules: List<Pair<String, String>>): Boolean {
        val clean = last10Digits(number)
        return rules.any { (ruleNum, tipo) ->
            val cleanRule = last10Digits(ruleNum)
            when (tipo.lowercase()) {
                "exacto" -> clean == cleanRule
                "prefijo" -> clean.startsWith(cleanRule)
                else -> false
            }
        }
    }
}