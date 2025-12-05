package com.example.untitled

import android.Manifest
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import com.polar.androidcommunications.api.ble.model.DisInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.PolarBleApiCallback
import com.polar.sdk.api.PolarBleApiDefaultImpl
import com.polar.sdk.api.model.*
//import com.polar.sdk.api.model.PolarDeviceInfo
//import com.polar.sdk.api.model.PolarHrData
//import com.polar.sdk.api.model.PolarEcgData
//import com.polar.sdk.api.model.PolarAccelerometerData
//import com.polar.sdk.api.model.PolarSensorSetting
//import java.util.UUID

import io.reactivex.rxjava3.android.schedulers.AndroidSchedulers
import io.reactivex.rxjava3.disposables.CompositeDisposable
import io.reactivex.rxjava3.disposables.Disposable
import io.reactivex.rxjava3.schedulers.Schedulers

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "PolarH10Demo"
        private const val METHOD_CHANNEL = "polar_h10_sdk/methods"
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    private lateinit var api: PolarBleApi
    private val disposables = CompositeDisposable()
    private var connectedDeviceId: String? = null

    private var ecgSink: EventChannel.EventSink? = null
    private var rrSink: EventChannel.EventSink? = null
    private var accSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestBlePermissions()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        api = PolarBleApiDefaultImpl.defaultImplementation(
            applicationContext,
            setOf(
                PolarBleApi.PolarBleSdkFeature.FEATURE_HR,
                PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_ONLINE_STREAMING
            )
        )

        api.setApiCallback(object : PolarBleApiCallback() {

            override fun blePowerStateChanged(powered: Boolean) {
                Log.d(TAG, "BLE power: $powered")
            }

            override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
                Log.d(TAG, "CONNECTED: ${polarDeviceInfo.deviceId}")
                connectedDeviceId = polarDeviceInfo.deviceId
            }

            override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
                Log.d(TAG, "CONNECTING: ${polarDeviceInfo.deviceId}")
            }

            override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
                Log.d(TAG, "DISCONNECTED: ${polarDeviceInfo.deviceId}")
                if (connectedDeviceId == polarDeviceInfo.deviceId) connectedDeviceId = null
            }

            override fun disInformationReceived(
                identifier: String,
                disInfo: DisInfo
            ) {
                Log.d(TAG, "DIS info: $identifier,  $disInfo")
            }

            override fun htsNotificationReceived(
                identifier: String,
                data: PolarHealthThermometerData
            ) {
                Log.d(TAG, "Thermometer Data: $identifier: $data")
            }

            /*
                        override fun disInformationReceived(identifier: String, uuid: UUID, value: String) {
                            Log.d(TAG, "DIS info: $identifier  $uuid = $value")
                        }
            */

            override fun batteryLevelReceived(identifier: String, level: Int) {
                Log.d(TAG, "Battery: $identifier  level = $level")
            }
        })


        // EVENT CHANNELS
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "polar_h10_sdk/ecg_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                ecgSink = events
                startEcg()
            }

            override fun onCancel(args: Any?) {
                ecgSink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "polar_h10_sdk/rr_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                rrSink = events
                startHr()
            }

            override fun onCancel(args: Any?) {
                rrSink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "polar_h10_sdk/acc_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                accSink = events
                startAcc()
            }

            override fun onCancel(args: Any?) {
                accSink = null
            }
        })


        // METHOD CHANNEL
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "searchAndConnect" -> searchAndConnect(result)
                "getOneHrSample" -> getOneHrSample(result)

                "startEcg" -> { startEcg(); result.success(null) }
                "startHr"  -> { startHr();  result.success(null) }
                "startAcc" -> { startAcc(); result.success(null) }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestBlePermissions() {
        val permissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_CONNECT
        } else {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
        }

        ActivityCompat.requestPermissions(
            this,
            permissions.toTypedArray(),
            PERMISSION_REQUEST_CODE
        )
    }

    private fun searchAndConnect(result: MethodChannel.Result) {
        val disposable = api.searchForDevice()
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe({ info ->
                Log.d(TAG, "Found: ${info.deviceId}")
                api.connectToDevice(info.deviceId)
                result.success(info.deviceId)
            }, { err ->
                result.error("SEARCH_ERROR", err.message, null)
            })

        disposables.add(disposable)
    }

    private fun getOneHrSample(result: MethodChannel.Result) {
        val id = connectedDeviceId ?: return result.error("NO_DEVICE", "Not connected", null)

        var disposable: Disposable? = null
        disposable = api.startHrStreaming(id)
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe({ hrData ->
                val sample = hrData.samples.firstOrNull()
                val hr = sample?.hr ?: -1
                result.success(hr)
                disposable?.dispose()
            }, { err ->
                result.error("HR_ERROR", err.message, null)
            })

        disposables.add(disposable!!)
    }

    private fun startEcg() {
        val id = connectedDeviceId ?: return

        val disposable = api.requestStreamSettings(id, PolarBleApi.PolarDeviceDataType.ECG)
            .flatMapPublisher { settings ->
                api.startEcgStreaming(id, settings)
            }
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe({ ecgData ->
                ecgData.samples.forEach { sample ->
                    when (sample) {

                        is EcgSample -> {
                            // sample.voltage is Int (microvolts)
                            val microVolts = sample.voltage
                            ecgSink?.success(microVolts)
                        }

                        is FecgSample -> {
                            // If you want fetal ECG, decide what to send.
                            val payload = mapOf(
                                "ecg" to sample.ecg,
                                "bioz" to sample.bioz,
                                "status" to sample.status.toInt()
                            )
                            ecgSink?.success(payload)
                        }
                    }
                }
            }, { error ->
                Log.e(TAG, "ECG stream error", error)
            })

        disposables.add(disposable)
    }

    private fun startAcc() {
        val id = connectedDeviceId ?: return

        val disposable = api.requestStreamSettings(id, PolarBleApi.PolarDeviceDataType.ACC)
            .flatMapPublisher { settings ->
                api.startAccStreaming(id, settings)
            }
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe({ acc: PolarAccelerometerData ->
                acc.samples.forEach { sample ->
                    accSink?.success(
                        mapOf(
                            "x" to sample.x,
                            "y" to sample.y,
                            "z" to sample.z
                        )
                    )
                }
            }, { err ->
                Log.e(TAG, "ACC error", err)
            })

        disposables.add(disposable)
    }

    private fun startHr() {
        val id = connectedDeviceId ?: return

        val disposable = api.startHrStreaming(id)
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe({ hrData: PolarHrData ->
                hrData.samples.forEach { sample ->
                    rrSink?.success(
                        mapOf(
                            "hr" to sample.hr,
                            "rr" to sample.rrsMs
                        )
                    )
                }
            }, { err ->
                Log.e(TAG, "HR error", err)
            })

        disposables.add(disposable)
    }

    override fun onDestroy() {
        super.onDestroy()
        disposables.clear()
        api.shutDown()
    }
}
