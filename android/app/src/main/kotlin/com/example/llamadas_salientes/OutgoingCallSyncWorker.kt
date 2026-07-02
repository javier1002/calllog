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

        fun getApiKey(context: Context): String {
            val prefs = context.getSharedPreferences("capsule_prefs", Context.MODE_PRIVATE)
            val fromPrefs = prefs.getString("api_key", "") ?: ""
            if (fromPrefs.isNotEmpty()) return fromPrefs
            return "ujfj8+XVhZZHA7FHlFqK+Mplc0HO8mEbXHYp59C177FbXS9fIt70x40jYoLu/4Y+"
        }
    }

    override fun doWork(): Result {
        android.util.Log.d("CAPSULE_WORKER", "🔵 doWork() iniciado")

        if (!hasRequiredPermissions()) {
            android.util.Log.d("CAPSULE_WORKER", "❌ Sin permisos")
            return Result.success()
        }

        android.util.Log.d("CAPSULE_WORKER", "✅ Permisos OK, iniciando sync...")

        return try {
            val db = openDatabase()
            ensureSchema(db)

            val now = System.currentTimeMillis()
            val from = now - 48L * 60 * 60 * 1000L

            val excludedRules = getExcludedRules(db)
            syncOutgoingCalls(db, excludedRules, from, now)

            val apiKey = getApiKey(applicationContext)
            android.util.Log.d("CAPSULE_WORKER", "🔑 API key vacía: ${apiKey.isEmpty()}")
            if (apiKey.isNotEmpty()) {
                syncToCapsule(db, apiKey)
            }

            db.close()
            Result.success()
        } catch (e: Exception) {
            android.util.Log.e("CAPSULE_WORKER", "❌ Error en doWork: ${e.message}")
            Result.retry()
        }
    }

    private fun syncToCapsule(db: android.database.sqlite.SQLiteDatabase, apiKey: String) {
        android.util.Log.d("CAPSULE_WORKER", "📤 syncToCapsule iniciado")
        var creadas = 0
        var omitidas = 0

        val cursor = db.query(
            "llamadas_salientes", null,
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

                if (numero.isBlank()) { omitidas++; continue }

                android.util.Log.d("CAPSULE_WORKER", "📱 Procesando: $numero")

                val partyId = findContactByPhone(numero, apiKey)
                if (partyId == null) { omitidas++; continue }

// Busca oportunidad directa en la persona
                var opportunityId = findManualCallOpportunity(partyId, numero, apiKey)

// Si no, busca en su organización
                if (opportunityId == null) {
                    val orgId = getOrganisationId(partyId, apiKey)
                    android.util.Log.d("CAPSULE_WORKER", "🏢 orgId para $partyId: $orgId")
                    if (orgId != null) {
                        opportunityId = findManualCallOpportunity(orgId, numero, apiKey)
                    }
                }

                if (opportunityId == null) { omitidas++; continue }


                val ok = addCallToOpportunity(opportunityId, numero, fecha, hora, duracion, estado, apiKey)
                if (ok) {
                    db.update(
                        "llamadas_salientes",
                        ContentValues().apply { put("sincronizado", 1) },
                        "id = ?",
                        arrayOf(callId.toString())
                    )
                    creadas++
                    android.util.Log.d("CAPSULE_WORKER", "✅ Sincronizado: $numero")
                } else {
                    omitidas++
                }
            }
        }

        val prefs = applicationContext.getSharedPreferences("capsule_prefs", Context.MODE_PRIVATE)
        prefs.edit().putString(
            "last_sync_result",
            "🔄 Sync automático\n✅ Creadas: $creadas\n⛔ Omitidas: $omitidas"
        ).apply()

        android.util.Log.d("CAPSULE_WORKER", "🏁 Creadas: $creadas, Omitidas: $omitidas")
    }

    private fun last10Digits(phone: String): String {
        val digits = phone.replace(Regex("[^0-9]"), "")
        return if (digits.length <= 10) digits else digits.substring(digits.length - 10)
    }

    private fun findContactByPhone(phoneNumber: String, apiKey: String): Int? {
        return try {
            val clean = last10Digits(phoneNumber)
            val url = URL("$CAPSULE_BASE/parties/search?q=$clean")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.setRequestProperty("Accept", "application/json")

            if (conn.responseCode != 200) return null

            val body = conn.inputStream.bufferedReader().readText()
            val parties = JSONObject(body).getJSONArray("parties")

            // Recolecta TODOS los partyIds que tienen este número
            val candidatos = mutableListOf<Int>()
            for (i in 0 until parties.length()) {
                val party = parties.getJSONObject(i)
                val phones = party.optJSONArray("phoneNumbers") ?: continue
                for (j in 0 until phones.length()) {
                    val num = phones.getJSONObject(j).optString("number", "")
                    if (last10Digits(num) == clean && clean.isNotEmpty()) {
                        candidatos.add(party.getInt("id"))
                        android.util.Log.d("CAPSULE_WORKER", "👤 Candidato: ${party.getInt("id")} - ${party.optString("firstName")} ${party.optString("lastName")} ${party.optString("name")}")
                    }
                }
            }

            if (candidatos.isEmpty()) return null

            // Devuelve el primero que tenga oportunidades
            for (partyId in candidatos) {
                val hasOpp = hasOpportunity(partyId, apiKey)
                android.util.Log.d("CAPSULE_WORKER", "🔍 partyId $partyId tiene oportunidad: $hasOpp")
                if (hasOpp) return partyId
            }

            // Si ninguno tiene oportunidad directa, intenta con sus organizaciones
            for (partyId in candidatos) {
                val orgId = getOrganisationId(partyId, apiKey)
                if (orgId != null) {
                    val hasOpp = hasOpportunity(orgId, apiKey)
                    android.util.Log.d("CAPSULE_WORKER", "🏢 orgId $orgId tiene oportunidad: $hasOpp")
                    if (hasOpp) return partyId // retorna la persona, no la org
                }
            }

            // Si nada funciona, retorna el primero
            candidatos.firstOrNull()
        } catch (e: Exception) {
            android.util.Log.e("CAPSULE_WORKER", "❌ findContactByPhone: ${e.message}")
            null
        }
    }

    private fun hasOpportunity(partyId: Int, apiKey: String): Boolean {
        return try {
            val url = URL("$CAPSULE_BASE/parties/$partyId/opportunities")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 10000
            conn.readTimeout = 10000
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.setRequestProperty("Accept", "application/json")
            if (conn.responseCode != 200) return false
            val body = conn.inputStream.bufferedReader().readText()
            JSONObject(body).getJSONArray("opportunities").length() > 0
        } catch (e: Exception) { false }
    }

    private fun getOrganisationId(personPartyId: Int, apiKey: String): Int? {
        return try {
            val url = URL("$CAPSULE_BASE/parties/$personPartyId?embed=organisation")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.setRequestProperty("Accept", "application/json")

            if (conn.responseCode != 200) return null

            val body = conn.inputStream.bufferedReader().readText()
            val party = JSONObject(body).optJSONObject("party") ?: return null
            val org = party.optJSONObject("organisation") ?: return null
            org.optInt("id", -1).takeIf { it != -1 }
        } catch (e: Exception) {
            android.util.Log.e("CAPSULE_WORKER", "❌ getOrganisationId: ${e.message}")
            null
        }
    }

    private fun findManualCallOpportunity(partyId: Int, phoneNumber: String, apiKey: String): Int? {
        return try {
            val url = URL("$CAPSULE_BASE/parties/$partyId/opportunities")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.setRequestProperty("Accept", "application/json")

            if (conn.responseCode != 200) {
                android.util.Log.d("CAPSULE_WORKER", "❌ Oportunidades status: ${conn.responseCode}")
                return null
            }

            val body = conn.inputStream.bufferedReader().readText()
            val opps = JSONObject(body).getJSONArray("opportunities")
            android.util.Log.d("CAPSULE_WORKER", "📋 Oportunidades para $partyId: ${opps.length()}")

            if (opps.length() == 0) {
                // Intenta buscar por organización
                android.util.Log.d("CAPSULE_WORKER", "⚠️ Sin oportunidades directas, intentando org...")
                return null
            }

            for (i in 0 until opps.length()) {
                val opp = opps.getJSONObject(i)
                android.util.Log.d("CAPSULE_WORKER", "   - id:${opp.getInt("id")} name:${opp.optString("name")}")
            }

            opps.getJSONObject(0).getInt("id")
        } catch (e: Exception) {
            android.util.Log.e("CAPSULE_WORKER", "❌ findManualCallOpportunity: ${e.message}")
            null
        }
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
        return try {
            val durationText = if (duracion > 0)
                "${duracion / 60}m ${duracion % 60}s"
            else "No respondida"

            val payload = JSONObject().apply {
                put("entry", JSONObject().apply {
                    put("type", "note")
                    put(
                        "content",
                        " Llamada saliente\n" +
                                "$phoneNumber\n" +
                                " $fecha   $hora\n" +
                                " Duración: $durationText\n" +
                                "Estado: $estado"
                    )
                    put("opportunity", JSONObject().apply { put("id", opportunityId) })
                })
            }

            val url = URL("$CAPSULE_BASE/entries")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")

            OutputStreamWriter(conn.outputStream).use { it.write(payload.toString()) }
            val code = conn.responseCode
            android.util.Log.d("CAPSULE_WORKER", "📝 Nota → $code")
            code in 200..299
        } catch (e: Exception) {
            android.util.Log.e("CAPSULE_WORKER", "❌ addCallToOpportunity: ${e.message}")
            false
        }
    }

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
            arrayOf(
                CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME,
                CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE
            ),
            "${CallLog.Calls.TYPE} = ? AND ${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.DATE} <= ?",
            arrayOf(
                CallLog.Calls.OUTGOING_TYPE.toString(),
                fromTimestamp.toString(),
                toTimestamp.toString()
            ),
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