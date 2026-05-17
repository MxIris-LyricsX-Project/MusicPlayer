import Foundation

#if os(macOS)
import AppKit
import MachO
#endif

public final class MediaController {
    private var listeningProcess: Process?
    private var dataBuffer = Data()
    private var isPlaying = false
    private var seekTimer: Timer?

    public var onTrackInfoReceived: ((TrackInfo?, [String: Any]?) -> Void)?
    public var onPlaybackStateReceived: ((Int?) -> Void)?
    public var onDecodingError: ((Error, Data) -> Void)?
    public var onListenerTerminated: (() -> Void)?

    public var bundleIdentifiers: [String] {
        didSet {
            if listeningProcess != nil {
                stopListening()
                startListening()
            }
        }
    }

    /// When `true`, the Perl bridge is launched with `--debug-dump`, which
    /// makes the dylib embed the full source NowPlayingInfo dictionary in
    /// every payload under the `__debugFullDump` key. Incoming lines that
    /// carry that field are logged via `NSLog` and `print` so the raw fields
    /// (including ones the adapter normally drops, e.g. lyric/subtitle keys
    /// from iOS-on-Mac apps) show up in the host process's console output.
    /// Toggling this restarts the listening process if it was already running.
    public var debugDumpEnabled: Bool = false {
        didSet {
            guard debugDumpEnabled != oldValue else { return }
            if listeningProcess != nil {
                stopListening()
                startListening()
            }
        }
    }

    public init(bundleIdentifiers: [String] = []) {
        self.bundleIdentifiers = bundleIdentifiers
    }

    private var perlScriptPath: String? {
        guard let path = Bundle.module.path(forResource: "run", ofType: "pl") else {
            assertionFailure("run.pl script not found in bundle resources.")
            return nil
        }
        return path
    }

    private var libraryPath: String? {
        let bundle = Bundle(for: MediaController.self)
        guard let path = bundle.executablePath else {
            assertionFailure("Could not locate the executable path for the MediaRemoteAdapter framework.")
            return nil
        }
        return path
    }

    @discardableResult
    private func runPerlCommand(arguments: [String]) -> (output: String?, error: String?, terminationStatus: Int32) {
        guard let scriptPath = perlScriptPath else {
            return (nil, "Perl script not found.", -1)
        }
        guard let libraryPath = libraryPath else {
            return (nil, "Dynamic library path not found.", -1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        var fullArguments = [scriptPath]
        if !bundleIdentifiers.isEmpty {
            fullArguments.append("--id")
            fullArguments.append(bundleIdentifiers.joined(separator: "|"))
        }
        if debugDumpEnabled {
            fullArguments.append("--debug-dump")
        }
        fullArguments.append(libraryPath)
        fullArguments.append(contentsOf: arguments)
        process.arguments = fullArguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Use buffers and readabilityHandler to avoid pipe deadlock.
        // The deadlock occurs when:
        // 1. Parent calls waitUntilExit() before reading pipe
        // 2. Child writes to stdout, filling the pipe buffer (typically 64KB)
        // 3. Child blocks on write, cannot exit
        // 4. Parent waits forever for child to exit
        var outputData = Data()
        var errorData = Data()
        let outputLock = NSLock()
        let errorLock = NSLock()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputLock.lock()
                outputData.append(data)
                outputLock.unlock()
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                errorLock.lock()
                errorData.append(data)
                errorLock.unlock()
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            // Stop the readability handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            // Read any remaining data
            outputLock.lock()
            let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputData.append(remainingOutput)
            outputLock.unlock()

            errorLock.lock()
            let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorData.append(remainingError)
            errorLock.unlock()

            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return (output, errorOutput, process.terminationStatus)
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return (nil, error.localizedDescription, -1)
        }
    }

    public func startListening() {
        guard listeningProcess == nil else {
            print("Listener process is already running.")
            return
        }

        guard let scriptPath = perlScriptPath else {
            return
        }
        guard let libraryPath = libraryPath else {
            return
        }

        listeningProcess = Process()
        listeningProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/perl")

        var arguments = [scriptPath]
        if !bundleIdentifiers.isEmpty {
            arguments.append("--id")
            arguments.append(bundleIdentifiers.joined(separator: "|"))
        }
        if debugDumpEnabled {
            arguments.append("--debug-dump")
        }
        arguments.append(contentsOf: [libraryPath, "loop"])
        listeningProcess?.arguments = arguments

        let outputPipe = Pipe()
        listeningProcess?.standardOutput = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self = self else { return }

            let incomingData = fileHandle.availableData
            if incomingData.isEmpty {
                // This can happen when the process terminates.
                return
            }

            self.dataBuffer.append(incomingData)

            // Process all complete lines in the buffer.
            while let range = self.dataBuffer.firstRange(of: "\n".data(using: .utf8)!) {
                let lineData = self.dataBuffer.subdata(in: 0 ..< range.lowerBound)

                // Remove the line and the newline character from the buffer.
                self.dataBuffer.removeSubrange(0 ..< range.upperBound)

                if !lineData.isEmpty {
                    processIncomingLine(lineData)
                }
            }
        }

        listeningProcess?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.listeningProcess = nil
                self?.onListenerTerminated?()
            }
        }

        do {
            try listeningProcess?.run()
        } catch {
            print("Failed to start listening process: \(error)")
            listeningProcess = nil
        }
    }

    private func processIncomingLine(_ lineData: Data, userInfo: [String: Any]? = nil) {
        guard !lineData.isEmpty else { return }
        do {
            let rawInfo = try JSONSerialization.jsonObject(with: lineData) as? [AnyHashable: Any] ?? [:]
            let notificationName = rawInfo["notificationName"] as? String ?? ""
            let payload = rawInfo["payload"] as? [AnyHashable: Any] ?? [:]

            // Surface the raw NowPlayingInfo dictionary when --debug-dump is on.
            // The dylib embeds it under `__debugFullDump`. Printing via NSLog
            // (visible in Console.app) and print (visible in Xcode's debugger
            // console) so it shows up regardless of how the host app was
            // launched. We also print a one-line client-identity summary that
            // resolves the source process to its bundle URL and runs the same
            // iOS-on-Mac heuristic the consumer-side code uses, so problem
            // reports include all the information needed to triage abuse.
            if let debugDump = payload["__debugFullDump"] {
                let bundleId = (payload["bundleIdentifier"] as? String) ?? "<nil>"
                let parentBundleId = (payload["parentApplicationBundleIdentifier"] as? String) ?? "<nil>"
                let appName = (payload["applicationName"] as? String) ?? "<nil>"
                let pidString = (payload["processIdentifier"] as? Int).map(String.init) ?? "<nil>"

                #if os(macOS)
                var bundleURLPath = "<nil>"
                var executablePath = "<nil>"
                var execArch = "<nil>"
                var platformString = "<unread>"
                var iosAppOnMacString = "false"
                if let pidInt = payload["processIdentifier"] as? Int,
                   let runningApp = NSRunningApplication(processIdentifier: pid_t(pidInt)) {
                    bundleURLPath = runningApp.bundleURL?.path ?? "<nil>"
                    executablePath = runningApp.executableURL?.path ?? "<nil>"
                    execArch = MediaController.formatExecutableArchitecture(runningApp.executableArchitecture)
                    if let executableURL = runningApp.executableURL,
                       let platform = MachOPlatformProbe.readPlatform(at: executableURL) {
                        platformString = MachOPlatformProbe.name(of: platform)
                    }
                    iosAppOnMacString = MediaController.isiOSAppOnMac(runningApp: runningApp) ? "true" : "false"
                }
                let summary = "[MediaRemoteAdapter] Client: bundle=\(bundleId), parent=\(parentBundleId), pid=\(pidString), name=\(appName), bundleURL=\(bundleURLPath), executable=\(executablePath), arch=\(execArch), platform=\(platformString), iOSAppOnMac=\(iosAppOnMacString)"
                #else
                let summary = "[MediaRemoteAdapter] Client: bundle=\(bundleId), parent=\(parentBundleId), pid=\(pidString), name=\(appName)"
                #endif
                NSLog("%@", summary)
                print(summary)
                NSLog("[MediaRemoteAdapter] NowPlayingInfo full dump = %@", String(describing: debugDump))
                print("[MediaRemoteAdapter] NowPlayingInfo full dump = \(debugDump)")
            }

            if notificationName == "kMRMediaRemoteNowPlayingInfoDidChangeNotification" {
                logIncomingInfoChange(payload: payload)
                let trackInfo: TrackInfo?
                if payload.isEmpty {
                    trackInfo = nil
                } else {
                    trackInfo = try JSONDecoder().decode(TrackInfo.self, from: JSONSerialization.data(withJSONObject: payload))
                }
                DispatchQueue.main.async {
                    self.onTrackInfoReceived?(trackInfo, userInfo)
                }
            } else if notificationName == "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification" {
                let playbackState = payload["playbackState"] as? Int
//                NSLog("[MediaRemoteAdapter][Flicker] PlaybackStateChange raw=%@ bundle=%@",
//                      playbackState.map(String.init) ?? "<nil>",
//                      (payload["bundleIdentifier"] as? String) ?? "<nil>")
                DispatchQueue.main.async {
                    self.onPlaybackStateReceived?(playbackState)
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.onDecodingError?(error, lineData)
            }
        }
    }

    /// One-line summary of an incoming NowPlayingInfo notification. Logs every
    /// inbound payload — frequency itself is the diagnostic signal for
    /// iOS-on-Mac apps that abuse the dictionary as a per-lyric-line ticker.
    private func logIncomingInfoChange(payload: [AnyHashable: Any]) {
        let title = (payload["title"] as? String) ?? "<nil>"
        let artist = (payload["artist"] as? String) ?? "<nil>"
        let album = (payload["album"] as? String) ?? "<nil>"
        let uniqueId = (payload["uniqueIdentifier"] as? Int).map(String.init) ?? "<nil>"
        let bundleId = (payload["bundleIdentifier"] as? String) ?? "<nil>"
        let parentBundleId = (payload["parentApplicationBundleIdentifier"] as? String) ?? "<nil>"
        let elapsedString: String
        if let elapsed = payload["elapsedTimeMicros"] as? Double {
            elapsedString = String(format: "%.3f", elapsed / 1_000_000)
        } else {
            elapsedString = "<nil>"
        }
        let isPlayingString: String
        if let isPlayingBool = payload["isPlaying"] as? Bool {
            isPlayingString = String(isPlayingBool)
        } else if let isPlayingInt = payload["isPlaying"] as? Int {
            isPlayingString = String(isPlayingInt == 1)
        } else {
            isPlayingString = "<nil>"
        }
//        NSLog("[MediaRemoteAdapter][Flicker] InfoChange uid=%@ isPlaying=%@ elapsed=%@s bundle=%@ parentBundle=%@ title=%@ artist=%@ album=%@",
//              uniqueId, isPlayingString, elapsedString, bundleId, parentBundleId, title, artist, album)
    }

    public func stopListening() {
        listeningProcess?.terminate()
        listeningProcess = nil
    }

    public func play() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["play"])
        }
    }

    public func pause() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["pause"])
        }
    }

    public func togglePlayPause() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["toggle_play_pause"])
        }
    }

    public func nextTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["next_track"])
        }
    }

    public func previousTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["previous_track"])
        }
    }

    public func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["stop"])
        }
    }

    public func updatePlayerState(userInfo: [String: Any] = [:]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runPerlCommand(arguments: ["update_player_state"])
            if let output = result.output, !output.isEmpty {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if let data = line.data(using: .utf8) {
                        self.processIncomingLine(data, userInfo: userInfo)
                    }
                }
            }
        }
    }

    public func setTime(seconds: Double) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["set_time", String(seconds)])
        }
    }

    #if os(macOS)
    /// Render a `cpu_type_t` value as a short human-readable name. Used only
    /// for debug logging — falls back to the raw integer for unknown types.
    static func formatExecutableArchitecture(_ arch: Int) -> String {
        switch arch {
        case 0x00000007: return "x86"
        case 0x0000000C: return "arm"
        case 0x01000007: return "x86_64"
        case 0x0100000C: return "arm64"
        default: return "raw=\(arch)"
        }
    }

    /// Detection of "iOS app running on Mac" by reading the
    /// `LC_BUILD_VERSION.platform` field of the app's Mach-O executable. iOS
    /// apps running on Apple Silicon Macs ship the original iOS-built binary,
    /// so platform = `PLATFORM_IOS` (2). Native macOS = `PLATFORM_MACOS` (1);
    /// Mac Catalyst = `PLATFORM_MACCATALYST` (6). The platform is set at link
    /// time and lives inside the Mach-O, so this reflects what the binary
    /// actually is regardless of bundle layout. Returns false if the binary
    /// can't be read or has no `LC_BUILD_VERSION` command.
    public static func isiOSAppOnMac(runningApp: NSRunningApplication?) -> Bool {
        guard let executableURL = runningApp?.executableURL,
              let platform = MachOPlatformProbe.readPlatform(at: executableURL) else {
            return false
        }
        return platform == MachOPlatformProbe.Platform.iOS
    }
    #endif
}

#if os(macOS)
/// Reads the `LC_BUILD_VERSION.platform` value from a Mach-O binary. We use
/// this to tell iOS-on-Mac apps (PLATFORM_IOS) apart from native macOS
/// (PLATFORM_MACOS) and Mac Catalyst (PLATFORM_MACCATALYST), since the host
/// can't always reach the wrapper bundle's Info.plist under sandboxing.
///
/// Fat-binary handling: we pick an arm64 slice when present (iOS-on-Mac is
/// Apple-Silicon-only, so this is the relevant slice), otherwise x86_64.
/// Endianness: fat headers are big-endian on disk; thin Mach-O headers and
/// load commands are written in their slice's native endianness.
enum MachOPlatformProbe {
    /// `LC_BUILD_VERSION.platform` constants (subset of `<mach-o/loader.h>`).
    enum Platform {
        static let macOS: UInt32 = 1
        static let iOS: UInt32 = 2
        static let tvOS: UInt32 = 3
        static let watchOS: UInt32 = 4
        static let bridgeOS: UInt32 = 5
        static let macCatalyst: UInt32 = 6
        static let iOSSimulator: UInt32 = 7
        static let tvOSSimulator: UInt32 = 8
        static let watchOSSimulator: UInt32 = 9
        static let driverKit: UInt32 = 10
    }

    static func name(of platform: UInt32) -> String {
        switch platform {
        case Platform.macOS:            return "macOS"
        case Platform.iOS:               return "iOS"
        case Platform.tvOS:              return "tvOS"
        case Platform.watchOS:           return "watchOS"
        case Platform.bridgeOS:          return "bridgeOS"
        case Platform.macCatalyst:       return "macCatalyst"
        case Platform.iOSSimulator:      return "iOSSimulator"
        case Platform.tvOSSimulator:     return "tvOSSimulator"
        case Platform.watchOSSimulator:  return "watchOSSimulator"
        case Platform.driverKit:         return "DriverKit"
        default:                         return "raw=\(platform)"
        }
    }

    static func readPlatform(at url: URL) -> UInt32? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return data.withUnsafeBytes(readPlatform(buffer:))
    }

    private static func readPlatform(buffer: UnsafeRawBufferPointer) -> UInt32? {
        guard buffer.count >= 8 else { return nil }
        let magic = buffer.load(fromByteOffset: 0, as: UInt32.self)

        let sliceOffset: Int
        switch magic {
        case FAT_CIGAM:
            guard let off = pickFatSlice(buffer: buffer, is64: false) else { return nil }
            sliceOffset = off
        case FAT_CIGAM_64:
            guard let off = pickFatSlice(buffer: buffer, is64: true) else { return nil }
            sliceOffset = off
        case MH_MAGIC, MH_MAGIC_64:
            sliceOffset = 0
        default:
            return nil
        }
        return readBuildVersion(buffer: buffer, offset: sliceOffset)
    }

    private static func pickFatSlice(buffer: UnsafeRawBufferPointer, is64: Bool) -> Int? {
        guard buffer.count >= MemoryLayout<fat_header>.size else { return nil }
        let header = buffer.load(fromByteOffset: 0, as: fat_header.self)
        let archCount = header.nfat_arch.byteSwapped

        var armSliceOffset: UInt64?
        var x86SliceOffset: UInt64?
        for archIndex in 0..<Int(archCount) {
            if is64 {
                let entryOffset = MemoryLayout<fat_header>.size + archIndex * MemoryLayout<fat_arch_64>.size
                guard entryOffset + MemoryLayout<fat_arch_64>.size <= buffer.count else { return nil }
                let arch = buffer.load(fromByteOffset: entryOffset, as: fat_arch_64.self)
                let cpuType = Int32(bitPattern: UInt32(bitPattern: arch.cputype).byteSwapped)
                let fileOffset = arch.offset.byteSwapped
                if cpuType == CPU_TYPE_ARM64 { armSliceOffset = fileOffset; break }
                if cpuType == CPU_TYPE_X86_64 { x86SliceOffset = fileOffset }
            } else {
                let entryOffset = MemoryLayout<fat_header>.size + archIndex * MemoryLayout<fat_arch>.size
                guard entryOffset + MemoryLayout<fat_arch>.size <= buffer.count else { return nil }
                let arch = buffer.load(fromByteOffset: entryOffset, as: fat_arch.self)
                let cpuType = Int32(bitPattern: UInt32(bitPattern: arch.cputype).byteSwapped)
                let fileOffset = UInt64(arch.offset.byteSwapped)
                if cpuType == CPU_TYPE_ARM64 { armSliceOffset = fileOffset; break }
                if cpuType == CPU_TYPE_X86_64 { x86SliceOffset = fileOffset }
            }
        }
        return (armSliceOffset ?? x86SliceOffset).map(Int.init)
    }

    private static func readBuildVersion(buffer: UnsafeRawBufferPointer, offset: Int) -> UInt32? {
        guard offset + MemoryLayout<mach_header>.size <= buffer.count else { return nil }
        let mhMagic = buffer.load(fromByteOffset: offset, as: UInt32.self)
        let is64: Bool
        switch mhMagic {
        case MH_MAGIC_64: is64 = true
        case MH_MAGIC:    is64 = false
        default:          return nil
        }
        let headerSize = is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        guard offset + headerSize <= buffer.count else { return nil }
        let ncmds: UInt32 = is64
            ? buffer.load(fromByteOffset: offset, as: mach_header_64.self).ncmds
            : buffer.load(fromByteOffset: offset, as: mach_header.self).ncmds

        var cursor = offset + headerSize
        let buildVersionCmd = UInt32(LC_BUILD_VERSION)
        for _ in 0..<Int(ncmds) {
            guard cursor + MemoryLayout<load_command>.size <= buffer.count else { return nil }
            let lc = buffer.load(fromByteOffset: cursor, as: load_command.self)
            if lc.cmd == buildVersionCmd {
                guard cursor + MemoryLayout<build_version_command>.size <= buffer.count else { return nil }
                let bvc = buffer.load(fromByteOffset: cursor, as: build_version_command.self)
                return bvc.platform
            }
            cursor += Int(lc.cmdsize)
        }
        return nil
    }
}
#endif
