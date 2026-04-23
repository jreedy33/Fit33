import Foundation
import CoreBluetooth
import Combine
import UIKit

// MARK: - FTMS UUIDs (Fitness Machine Service Standard)
struct FTMSUUIDs {
    // Service UUIDs
    static let fitnesseMachineService = CBUUID(string: "1826")
    static let heartRateService = CBUUID(string: "180D")
    static let cyclingPowerService = CBUUID(string: "1818")
    static let cyclingSpeedCadenceService = CBUUID(string: "1816")
    static let runningSpeedCadenceService = CBUUID(string: "1814")
    
    // Characteristic UUIDs
    static let treadmillData = CBUUID(string: "2ACD")
    static let crossTrainerData = CBUUID(string: "2ACE")
    static let rowerData = CBUUID(string: "2AD1")
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let cyclingPowerMeasurement = CBUUID(string: "2A63")
    static let fitnesseMachineFeature = CBUUID(string: "2ACC")
    static let fitnesseMachineStatus = CBUUID(string: "2ADA")
    static let fitnesseMachineControlPoint = CBUUID(string: "2AD9")
    static let supportedPowerRange = CBUUID(string: "2AD8")
    static let supportedResistanceLevelRange = CBUUID(string: "2AD6")
    static let supportedInclinationRange = CBUUID(string: "2AD5")
    static let supportedSpeedRange = CBUUID(string: "2AD4")
}

// MARK: - Equipment Types
enum FitnessEquipmentType: String, CaseIterable {
    case treadmill = "Treadmill"
    case indoorBike = "Indoor Bike"
    case rower = "Rowing Machine"
    case elliptical = "Elliptical"
    case unknown = "Fitness Equipment"
    
    var icon: String {
        switch self {
        case .treadmill: return "figure.run"
        case .indoorBike: return "figure.indoor.cycle"
        case .rower: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .unknown: return "dumbbell.fill"
        }
    }
    
    var color: (primary: String, secondary: String) {
        switch self {
        case .treadmill: return ("#34C759", "#30D158")
        case .indoorBike: return ("#FF9500", "#FF9F0A")
        case .rower: return ("#007AFF", "#0A84FF")
        case .elliptical: return ("#AF52DE", "#BF5AF2")
        case .unknown: return ("#8E8E93", "#98989D")
        }
    }
}

// MARK: - Discovered Device
struct DiscoveredFitnessDevice: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let type: FitnessEquipmentType
    var rssi: Int
    var lastSeen: Date
    
    static func == (lhs: DiscoveredFitnessDevice, rhs: DiscoveredFitnessDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Live Equipment Data
struct FitnessEquipmentData {
    // Common metrics
    var speed: Double = 0 // km/h
    var distance: Double = 0 // meters
    var elapsedTime: TimeInterval = 0 // seconds
    var calories: Int = 0
    var heartRate: Int = 0
    
    // Treadmill specific
    var incline: Double = 0 // percentage
    var pace: Double = 0 // min/km
    
    // Bike specific
    var cadence: Int = 0 // RPM
    var power: Int = 0 // watts
    var resistance: Int = 0 // level
    
    // Rower specific
    var strokeRate: Int = 0 // strokes/min
    var strokeCount: Int = 0
    var splitTime: TimeInterval = 0 // per 500m
    
    var timestamp: Date = Date()
}

// MARK: - Connection State
enum EquipmentConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)
    
    var description: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Bluetooth Fitness Manager
class BluetoothFitnessManager: NSObject, ObservableObject {
    static let shared = BluetoothFitnessManager()
    
    // Published properties
    @Published var connectionState: EquipmentConnectionState = .disconnected
    @Published var discoveredDevices: [DiscoveredFitnessDevice] = []
    @Published var connectedDevice: DiscoveredFitnessDevice?
    @Published var liveData: FitnessEquipmentData = FitnessEquipmentData()
    @Published var isBluetoothAvailable = false
    @Published var isScanning = false
    
    // Core Bluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var dataCharacteristics: [CBCharacteristic] = []
    
    // Timers
    private var scanTimer: Timer?
    private var cleanupTimer: Timer?
    
    // Workout recording
    private var workoutStartTime: Date?
    private var dataHistory: [FitnessEquipmentData] = []
    
    // RSSI averaging for stable proximity ranking (5-sample rolling average)
    private var rssiHistory: [UUID: [Int]] = [:]
    private let rssiSampleCount = 5
    
    // Device memory — remember last connected device for quick reconnect
    private var lastDeviceId: String {
        get { UserDefaults.standard.string(forKey: "lastConnectedBLEDeviceId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastConnectedBLEDeviceId") }
    }
    private var lastDeviceName: String {
        get { UserDefaults.standard.string(forKey: "lastConnectedBLEDeviceName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastConnectedBLEDeviceName") }
    }
    
    // Auto-suggest: the device we're most confident is the user's (closest by RSSI)
    var suggestedDevice: DiscoveredFitnessDevice? {
        guard discoveredDevices.count >= 2 else { return discoveredDevices.first }
        let strongest = discoveredDevices[0]
        let secondStrongest = discoveredDevices[1]
        if strongest.rssi - secondStrongest.rssi >= 15 { return strongest }
        return nil
    }
    
    // The remembered device if it appears in the current scan
    var rememberedDevice: DiscoveredFitnessDevice? {
        guard !lastDeviceId.isEmpty else { return nil }
        return discoveredDevices.first { $0.peripheral.identifier.uuidString == lastDeviceId }
    }
    
    // Whether we should auto-connect (remembered device is also the closest)
    var shouldAutoConnect: Bool {
        guard let remembered = rememberedDevice,
              let suggested = suggestedDevice else { return false }
        return remembered.id == suggested.id
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        observeAppLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Pause the 30s auto-stop + 5s cleanup timers while the app is backgrounded.
    /// iOS suspends BLE scans for apps without `bluetooth-central` background mode,
    /// so the timers wake the main thread for no observable work. When we come back,
    /// if scanning is still active we restart them so the 30s auto-stop budget is honored.
    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleDidEnterBackground() {
        scanTimer?.invalidate()
        cleanupTimer?.invalidate()
    }

    @objc private func handleWillEnterForeground() {
        guard isScanning else { return }
        // Relight the cleanup cadence only; we intentionally drop the 30s auto-stop
        // once we've been backgrounded — foregrounding is a clear signal the user
        // is still interacting, and they'll stop scanning manually or start fresh.
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.cleanupStaleDevices()
        }
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard isBluetoothAvailable else {
            connectionState = .error("Bluetooth not available")
            return
        }
        
        discoveredDevices.removeAll()
        rssiHistory.removeAll()
        connectionState = .scanning
        isScanning = true
        
        // Scan for FTMS and related services
        centralManager.scanForPeripherals(
            withServices: [
                FTMSUUIDs.fitnesseMachineService,
                FTMSUUIDs.heartRateService,
                FTMSUUIDs.cyclingPowerService
            ],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        
        // Auto-stop scanning after 30 seconds
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
        
        // Cleanup old devices every 5 seconds
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.cleanupStaleDevices()
        }
        
        AppLogger.debug("🔵 [BLUETOOTH] Started scanning for fitness equipment", category: .health)
    }
    
    func stopScanning() {
        centralManager.stopScan()
        scanTimer?.invalidate()
        cleanupTimer?.invalidate()
        isScanning = false
        
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        
        AppLogger.debug("🔵 [BLUETOOTH] Stopped scanning", category: .health)
    }
    
    func connect(to device: DiscoveredFitnessDevice) {
        stopScanning()
        connectionState = .connecting
        
        lastDeviceId = device.peripheral.identifier.uuidString
        lastDeviceName = device.name
        
        AppLogger.debug("🔵 [BLUETOOTH] Connecting to \(device.name)...", category: .health)
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        connectedPeripheral = nil
        connectedDevice = nil
        connectionState = .disconnected
        liveData = FitnessEquipmentData()
        dataCharacteristics.removeAll()
        
        AppLogger.debug("🔵 [BLUETOOTH] Disconnected from equipment", category: .health)
    }
    
    func startWorkoutRecording() {
        workoutStartTime = Date()
        dataHistory.removeAll()
        AppLogger.debug("🔵 [BLUETOOTH] Started workout recording", category: .health)
    }
    
    func stopWorkoutRecording() -> (duration: TimeInterval, distance: Double, calories: Int, avgHeartRate: Int)? {
        guard let startTime = workoutStartTime else { return nil }
        
        let duration = Date().timeIntervalSince(startTime)
        let distance = liveData.distance
        let calories = liveData.calories
        
        // Calculate average heart rate from history
        let heartRates = dataHistory.compactMap { $0.heartRate > 0 ? $0.heartRate : nil }
        let avgHeartRate = heartRates.isEmpty ? 0 : heartRates.reduce(0, +) / heartRates.count
        
        workoutStartTime = nil
        
        AppLogger.debug("🔵 [BLUETOOTH] Stopped recording: \(duration)s, \(distance)m, \(calories)cal, \(avgHeartRate)bpm avg", category: .health)
        
        return (duration, distance, calories, avgHeartRate)
    }
    
    // MARK: - Private Methods
    
    private func cleanupStaleDevices() {
        let cutoff = Date().addingTimeInterval(-10)
        let staleIds = discoveredDevices.filter { $0.lastSeen < cutoff }.map { $0.id }
        discoveredDevices.removeAll { $0.lastSeen < cutoff }
        for id in staleIds { rssiHistory.removeValue(forKey: id) }
    }
    
    private func determineEquipmentType(from advertisementData: [String: Any], name: String) -> FitnessEquipmentType {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("treadmill") || lowercaseName.contains("tread") || lowercaseName.contains("run") {
            return .treadmill
        } else if lowercaseName.contains("bike") || lowercaseName.contains("cycle") || lowercaseName.contains("spin") {
            return .indoorBike
        } else if lowercaseName.contains("row") || lowercaseName.contains("erg") || lowercaseName.contains("concept") {
            return .rower
        } else if lowercaseName.contains("elliptical") || lowercaseName.contains("cross") || lowercaseName.contains("trainer") {
            return .elliptical
        }
        
        return .unknown
    }
    
    private func discoverServices(for peripheral: CBPeripheral) {
        peripheral.discoverServices([
            FTMSUUIDs.fitnesseMachineService,
            FTMSUUIDs.heartRateService,
            FTMSUUIDs.cyclingPowerService
        ])
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothFitnessManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            isBluetoothAvailable = true
            AppLogger.debug("🔵 [BLUETOOTH] Powered on and ready", category: .health)
        case .poweredOff:
            isBluetoothAvailable = false
            connectionState = .error("Bluetooth is turned off")
            AppLogger.debug("🔵 [BLUETOOTH] Powered off", category: .health)
        case .unauthorized:
            isBluetoothAvailable = false
            connectionState = .error("Bluetooth permission denied")
            AppLogger.debug("🔵 [BLUETOOTH] Unauthorized", category: .health)
        case .unsupported:
            isBluetoothAvailable = false
            connectionState = .error("Bluetooth not supported")
            AppLogger.debug("🔵 [BLUETOOTH] Unsupported", category: .health)
        default:
            isBluetoothAvailable = false
            AppLogger.debug("🔵 [BLUETOOTH] State: \(central.state.rawValue)", category: .health)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
        
        guard name != "Unknown Device" else { return }
        
        let equipmentType = determineEquipmentType(from: advertisementData, name: name)
        
        // RSSI averaging: keep last N samples for stable proximity ranking
        let deviceId = peripheral.identifier
        rssiHistory[deviceId, default: []].append(RSSI.intValue)
        if let history = rssiHistory[deviceId], history.count > rssiSampleCount {
            rssiHistory[deviceId]?.removeFirst()
        }
        let history = rssiHistory[deviceId] ?? []
        let avgRSSI = history.isEmpty ? RSSI.intValue : history.reduce(0, +) / history.count
        
        if let index = discoveredDevices.firstIndex(where: { $0.peripheral.identifier == deviceId }) {
            discoveredDevices[index].rssi = avgRSSI
            discoveredDevices[index].lastSeen = Date()
        } else {
            let device = DiscoveredFitnessDevice(
                id: deviceId,
                peripheral: peripheral,
                name: name,
                type: equipmentType,
                rssi: avgRSSI,
                lastSeen: Date()
            )
            discoveredDevices.append(device)
            AppLogger.debug("🔵 [BLUETOOTH] Discovered: \(name) (\(equipmentType.rawValue)) RSSI: \(avgRSSI)", category: .health)
        }
        
        discoveredDevices.sort { $0.rssi > $1.rssi }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        AppLogger.debug("🔵 [BLUETOOTH] Connected to \(peripheral.name ?? "device")", category: .health)
        
        connectedPeripheral = peripheral
        peripheral.delegate = self
        
        // Find the device info
        if let device = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            connectedDevice = device
        }
        
        connectionState = .connected
        discoverServices(for: peripheral)
        
        HapticManager.notification(.success)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        AppLogger.error("🔵 [BLUETOOTH] Failed to connect: \(error?.localizedDescription ?? "unknown error")", category: .health)
        connectionState = .error(error?.localizedDescription ?? "Connection failed")
        HapticManager.notification(.error)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        AppLogger.debug("🔵 [BLUETOOTH] Disconnected from \(peripheral.name ?? "device")", category: .health)
        
        connectedPeripheral = nil
        connectedDevice = nil
        connectionState = .disconnected
        dataCharacteristics.removeAll()
        
        if error != nil {
            HapticManager.notification(.warning)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothFitnessManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            AppLogger.debug("🔵 [BLUETOOTH] Discovered service: \(service.uuid)", category: .health)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            AppLogger.debug("🔵 [BLUETOOTH] Discovered characteristic: \(characteristic.uuid)", category: .health)
            
            // Subscribe to notify characteristics
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
                dataCharacteristics.append(characteristic)
            }
            
            // Read readable characteristics
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case FTMSUUIDs.treadmillData:
            parseTreadmillData(data)
        case FTMSUUIDs.indoorBikeData:
            parseIndoorBikeData(data)
        case FTMSUUIDs.rowerData:
            parseRowerData(data)
        case FTMSUUIDs.crossTrainerData:
            parseCrossTrainerData(data)
        case FTMSUUIDs.heartRateMeasurement:
            parseHeartRateData(data)
        case FTMSUUIDs.cyclingPowerMeasurement:
            parsePowerData(data)
        default:
            break
        }
        
        // Record data point for workout
        if workoutStartTime != nil {
            dataHistory.append(liveData)
            if dataHistory.count > 3600 {
                dataHistory.removeFirst(dataHistory.count - 3600)
            }
        }
    }
    
    // MARK: - Data Parsing
    
    private func parseTreadmillData(_ data: Data) {
        guard data.count >= 2 else { return }
        
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2
        
        // Instantaneous Speed (always present) - resolution 0.01 km/h
        if data.count >= offset + 2 {
            let speedRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.speed = Double(speedRaw) * 0.01
            liveData.pace = liveData.speed > 0 ? 60.0 / liveData.speed : 0
            offset += 2
        }
        
        // Average Speed (if flag bit 1 is set)
        if flags & 0x0002 != 0 && data.count >= offset + 2 {
            offset += 2
        }
        
        // Total Distance (if flag bit 2 is set) - resolution 1 meter
        if flags & 0x0004 != 0 && data.count >= offset + 3 {
            let distanceRaw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
            liveData.distance = Double(distanceRaw)
            offset += 3
        }
        
        // Inclination (if flag bit 3 is set)
        if flags & 0x0008 != 0 && data.count >= offset + 4 {
            let inclineRaw = Int16(data[offset]) | (Int16(data[offset + 1]) << 8)
            liveData.incline = Double(inclineRaw) * 0.1
            offset += 4
        }
        
        // Elapsed Time (if flag bit 7 is set)
        if flags & 0x0080 != 0 && data.count >= offset + 2 {
            let timeRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.elapsedTime = Double(timeRaw)
            offset += 2
        }
        
        // Energy (if flag bit 9 is set)
        if flags & 0x0200 != 0 && data.count >= offset + 5 {
            let totalEnergy = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.calories = Int(totalEnergy)
            offset += 5
        }
        
        // Heart Rate (if flag bit 10 is set)
        if flags & 0x0400 != 0 && data.count >= offset + 1 {
            liveData.heartRate = Int(data[offset])
        }
        
        liveData.timestamp = Date()
    }
    
    private func parseIndoorBikeData(_ data: Data) {
        guard data.count >= 2 else { return }
        
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2
        
        // Instantaneous Speed (if flag bit 0 is NOT set) - resolution 0.01 km/h
        if flags & 0x0001 == 0 && data.count >= offset + 2 {
            let speedRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.speed = Double(speedRaw) * 0.01
            offset += 2
        }
        
        // Instantaneous Cadence (if flag bit 2 is set) - resolution 0.5 rpm
        if flags & 0x0004 != 0 && data.count >= offset + 2 {
            let cadenceRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.cadence = Int(Double(cadenceRaw) * 0.5)
            offset += 2
        }
        
        // Total Distance (if flag bit 4 is set)
        if flags & 0x0010 != 0 && data.count >= offset + 3 {
            let distanceRaw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
            liveData.distance = Double(distanceRaw)
            offset += 3
        }
        
        // Resistance Level (if flag bit 5 is set)
        if flags & 0x0020 != 0 && data.count >= offset + 2 {
            let resistanceRaw = Int16(data[offset]) | (Int16(data[offset + 1]) << 8)
            liveData.resistance = Int(resistanceRaw)
            offset += 2
        }
        
        // Instantaneous Power (if flag bit 6 is set)
        if flags & 0x0040 != 0 && data.count >= offset + 2 {
            let powerRaw = Int16(data[offset]) | (Int16(data[offset + 1]) << 8)
            liveData.power = Int(powerRaw)
            offset += 2
        }
        
        // Energy (if flag bit 8 is set)
        if flags & 0x0100 != 0 && data.count >= offset + 5 {
            let totalEnergy = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.calories = Int(totalEnergy)
            offset += 5
        }
        
        // Heart Rate (if flag bit 9 is set)
        if flags & 0x0200 != 0 && data.count >= offset + 1 {
            liveData.heartRate = Int(data[offset])
            offset += 1
        }
        
        // Elapsed Time (if flag bit 10 is set)
        if flags & 0x0400 != 0 && data.count >= offset + 2 {
            let timeRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.elapsedTime = Double(timeRaw)
        }
        
        liveData.timestamp = Date()
    }
    
    private func parseRowerData(_ data: Data) {
        guard data.count >= 2 else { return }
        
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2
        
        // Stroke Rate (if flag bit 0 is NOT set) - resolution 0.5 strokes/min
        if flags & 0x0001 == 0 && data.count >= offset + 1 {
            let strokeRateRaw = data[offset]
            liveData.strokeRate = Int(Double(strokeRateRaw) * 0.5)
            offset += 1
        }
        
        // Stroke Count (if flag bit 0 is NOT set)
        if flags & 0x0001 == 0 && data.count >= offset + 2 {
            let strokeCountRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.strokeCount = Int(strokeCountRaw)
            offset += 2
        }
        
        // Total Distance (if flag bit 2 is set)
        if flags & 0x0004 != 0 && data.count >= offset + 3 {
            let distanceRaw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
            liveData.distance = Double(distanceRaw)
            offset += 3
        }
        
        // Instantaneous Pace (if flag bit 3 is set) - seconds per 500m
        if flags & 0x0008 != 0 && data.count >= offset + 2 {
            let paceRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.splitTime = Double(paceRaw)
            offset += 2
        }
        
        // Instantaneous Power (if flag bit 5 is set)
        if flags & 0x0020 != 0 && data.count >= offset + 2 {
            let powerRaw = Int16(data[offset]) | (Int16(data[offset + 1]) << 8)
            liveData.power = Int(powerRaw)
            offset += 2
        }
        
        // Energy (if flag bit 8 is set)
        if flags & 0x0100 != 0 && data.count >= offset + 5 {
            let totalEnergy = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.calories = Int(totalEnergy)
            offset += 5
        }
        
        // Heart Rate (if flag bit 9 is set)
        if flags & 0x0200 != 0 && data.count >= offset + 1 {
            liveData.heartRate = Int(data[offset])
            offset += 1
        }
        
        // Elapsed Time (if flag bit 10 is set)
        if flags & 0x0400 != 0 && data.count >= offset + 2 {
            let timeRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.elapsedTime = Double(timeRaw)
        }
        
        liveData.timestamp = Date()
    }
    
    private func parseCrossTrainerData(_ data: Data) {
        guard data.count >= 3 else { return }
        
        let flags = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16)
        var offset = 3
        
        // Instantaneous Speed (if flag bit 0 is NOT set)
        if flags & 0x000001 == 0 && data.count >= offset + 2 {
            let speedRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.speed = Double(speedRaw) * 0.01
            offset += 2
        }
        
        // Step Count (if flag bit 2 is set)
        if flags & 0x000004 != 0 && data.count >= offset + 2 {
            offset += 2 // Skip for now
        }
        
        // Stride Count (if flag bit 3 is set)
        if flags & 0x000008 != 0 && data.count >= offset + 2 {
            let strideCountRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.strokeCount = Int(strideCountRaw)
            offset += 2
        }
        
        // Total Distance (if flag bit 6 is set)
        if flags & 0x000040 != 0 && data.count >= offset + 3 {
            let distanceRaw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
            liveData.distance = Double(distanceRaw)
            offset += 3
        }
        
        // Resistance Level (if flag bit 7 is set)
        if flags & 0x000080 != 0 && data.count >= offset + 2 {
            let resistanceRaw = Int16(data[offset]) | (Int16(data[offset + 1]) << 8)
            liveData.resistance = Int(resistanceRaw)
            offset += 2
        }
        
        // Instantaneous Power (if flag bit 8 is set)
        if flags & 0x000100 != 0 && data.count >= offset + 2 {
            let powerRaw = Int16(data[offset]) | (Int16(data[offset + 1]) << 8)
            liveData.power = Int(powerRaw)
            offset += 2
        }
        
        // Energy (if flag bit 10 is set)
        if flags & 0x000400 != 0 && data.count >= offset + 5 {
            let totalEnergy = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.calories = Int(totalEnergy)
            offset += 5
        }
        
        // Heart Rate (if flag bit 11 is set)
        if flags & 0x000800 != 0 && data.count >= offset + 1 {
            liveData.heartRate = Int(data[offset])
            offset += 1
        }
        
        // Elapsed Time (if flag bit 12 is set)
        if flags & 0x001000 != 0 && data.count >= offset + 2 {
            let timeRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            liveData.elapsedTime = Double(timeRaw)
        }
        
        liveData.timestamp = Date()
    }
    
    private func parseHeartRateData(_ data: Data) {
        guard data.count >= 2 else { return }
        
        let flags = data[0]
        
        // Check if heart rate is 8-bit or 16-bit
        if flags & 0x01 == 0 {
            // 8-bit heart rate
            liveData.heartRate = Int(data[1])
        } else if data.count >= 3 {
            // 16-bit heart rate
            liveData.heartRate = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
        }
    }
    
    private func parsePowerData(_ data: Data) {
        guard data.count >= 4 else { return }
        
        // Skip flags (2 bytes)
        let powerRaw = Int16(data[2]) | (Int16(data[3]) << 8)
        liveData.power = Int(powerRaw)
    }
}
