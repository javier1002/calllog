package com.example.llamadas_salientes

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CallLog
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val channelName = "registro_llamadas/call_log"
    private val permissionRequestCode = 7001
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Corre el worker inmediatamente para pruebas — quita esto en producción
        testWorkerNow()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCallPermissions" -> requestCallPermissions(result)

                "saveApiKey" -> {
                    val key = call.argument<String>("key") ?: ""
                    val prefs = getSharedPreferences("capsule_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putString("api_key", key).apply()
                    result.success(true)
                }

                "getLastSyncResult" -> {
                    val prefs = getSharedPreferences("capsule_prefs", Context.MODE_PRIVATE)
                    val msg = prefs.getString("last_sync_result", null)
                    if (msg != null) {
                        prefs.edit().remove("last_sync_result").apply()
                    }
                    result.success(msg)
                }

                "getOutgoingCalls" -> {
                    if (!hasRequiredPermissions()) {
                        result.error("PERMISSION_DENIED", "No se concedieron los permisos necesarios.", null)
                        return@setMethodCallHandler
                    }
                    val from = getLongArgument(call, "from", 0L)
                    val to = getLongArgument(call, "to", System.currentTimeMillis())
                    try {
                        result.success(getOutgoingCalls(from, to))
                    } catch (error: Exception) {
                        result.error("CALL_LOG_ERROR", error.message ?: "Error leyendo el registro de llamadas.", null)
                    }
                }

                "scheduleDailyCallSync" -> {
                    if (!hasRequiredPermissions()) {
                        result.error("PERMISSION_DENIED", "No se concedieron los permisos necesarios.", null)
                        return@setMethodCallHandler
                    }
                    scheduleDailyCallSync()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        if (hasRequiredPermissions()) {
            scheduleDailyCallSync()
        }
    }

    private fun testWorkerNow() {
        android.util.Log.d("CAPSULE_TEST", "🔵 Encolando worker de prueba...")
        val request = OneTimeWorkRequestBuilder<OutgoingCallSyncWorker>()
            .addTag("test_immediate")
            .build()
        WorkManager.getInstance(this).enqueueUniqueWork(
            "test_immediate",
            ExistingWorkPolicy.REPLACE,
            request
        )
    }

    private fun requestCallPermissions(result: MethodChannel.Result) {
        if (hasRequiredPermissions()) {
            scheduleDailyCallSync()
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            scheduleDailyCallSync()
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_REQUEST_ACTIVE", "Ya existe una solicitud de permisos en curso.", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_CALL_LOG, Manifest.permission.READ_CONTACTS),
            permissionRequestCode
        )
    }

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (granted) scheduleDailyCallSync()
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun getOutgoingCalls(fromTimestamp: Long, toTimestamp: Long): List<Map<String, Any?>> {
        val calls = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME,
            CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE
        )
        val selection = "${CallLog.Calls.TYPE} = ? AND ${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.DATE} <= ?"
        val selectionArgs = arrayOf(
            CallLog.Calls.OUTGOING_TYPE.toString(),
            fromTimestamp.toString(),
            toTimestamp.toString()
        )
        val cursor = contentResolver.query(
            CallLog.Calls.CONTENT_URI, projection, selection, selectionArgs,
            "${CallLog.Calls.DATE} DESC"
        )
        cursor?.use {
            val androidIdIndex = it.getColumnIndexOrThrow(CallLog.Calls._ID)
            val numberIndex = it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
            val nameIndex = it.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)
            val dateIndex = it.getColumnIndexOrThrow(CallLog.Calls.DATE)
            val durationIndex = it.getColumnIndexOrThrow(CallLog.Calls.DURATION)
            val dateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val timeFormatter = SimpleDateFormat("HH:mm", Locale.US)
            while (it.moveToNext()) {
                val timestamp = it.getLong(dateIndex)
                val duration = it.getInt(durationIndex)
                calls.add(mapOf(
                    "android_id" to it.getLong(androidIdIndex),
                    "numero" to (it.getString(numberIndex) ?: ""),
                    "nombre_contacto" to (it.getString(nameIndex) ?: ""),
                    "fecha" to dateFormatter.format(Date(timestamp)),
                    "hora" to timeFormatter.format(Date(timestamp)),
                    "duracion" to duration,
                    "estado" to if (duration > 0) "Respondida" else "No respondida",
                    "timestamp" to timestamp
                ))
            }
        }
        return calls
    }

    private fun getLongArgument(call: MethodCall, key: String, defaultValue: Long): Long {
        return when (val value = call.argument<Any>(key) ?: return defaultValue) {
            is Int -> value.toLong()
            is Long -> value
            is Double -> value.toLong()
            is Float -> value.toLong()
            else -> defaultValue
        }
    }

    private fun scheduleDailyCallSync() {
        val initialDelay = calculateInitialDelayMillis(
            targetHour = 11,
            targetMinute = 59
        )
        val request = PeriodicWorkRequestBuilder<OutgoingCallSyncWorker>(1, TimeUnit.DAYS)
            .setInitialDelay(initialDelay, TimeUnit.MILLISECONDS)
            .addTag(OutgoingCallSyncWorker.WORK_NAME)
            .build()

        // REPLACE: siempre toma el horario actualizado
        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            OutgoingCallSyncWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.REPLACE,
            request
        )
    }

    private fun calculateInitialDelayMillis(targetHour: Int, targetMinute: Int): Long {
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, targetHour)
            set(Calendar.MINUTE, targetMinute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_YEAR, 1)
        }
        return target.timeInMillis - now.timeInMillis
    }
}