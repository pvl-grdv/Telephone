//
//  AKSIPUserAgent.swift
//  Telephone
//
//  Swift implementation of Telephone's PJSIP runtime.
//

import Foundation
import UseCases

@objc @implementation
extension AKSIPUserAgent {
    private final let storage = SIPUserAgentStorage()

    public var delegate: (any AKSIPUserAgentDelegate)? {
        get { storage.delegate }
        set {
            if let oldDelegate = storage.delegate, oldDelegate !== newValue {
                unsubscribe(oldDelegate, from: self)
            }
            if let newValue, storage.delegate !== newValue {
                subscribe(newValue, to: self)
            }
            storage.delegate = newValue
        }
    }

    public var isStarted: Bool {
        storage.state.rawValue == 2
    }

    public var state: AKSIPUserAgentState {
        storage.state
    }

    public var detectedNATType: AKNATType {
        get { storage.detectedNATType }
        set { storage.detectedNATType = newValue }
    }

    public var activeCallsCount: Int {
        storage.accounts.reduce(0) {
            $0 + $1.activeCallsCount()
        }
    }

    public var hasUnansweredIncomingCalls: Bool {
        storage.accounts.contains(\.hasUnansweredIncomingCalls)
    }

    public var callData: UnsafeMutablePointer<AKSIPUserAgentCallData> {
        storage.callData
    }

    public var maxCalls: Int {
        get { storage.maxCalls }
        set { storage.maxCalls = newValue }
    }

    public var nameServers: [String] {
        get { storage.nameServers }
        set { storage.nameServers = Array(newValue.prefix(4)) }
    }

    public var outboundProxyHost: String {
        get { storage.outboundProxyHost }
        set { storage.outboundProxyHost = newValue }
    }

    public var outboundProxyPort: UInt {
        get { storage.outboundProxyPort }
        set {
            storage.outboundProxyPort =
                (1...65_535).contains(newValue)
                    ? newValue
                    : 5_060
        }
    }

    public var STUNServerHost: String {
        get { storage.stunServerHost }
        set { storage.stunServerHost = newValue }
    }

    public var STUNServerPort: UInt {
        get { storage.stunServerPort }
        set {
            storage.stunServerPort =
                (1...65_535).contains(newValue)
                    ? newValue
                    : 3_478
        }
    }

    public var userAgentString: String {
        get { storage.userAgentString }
        set { storage.userAgentString = newValue }
    }

    public var logFileName: String {
        get { storage.logFileName }
        set { storage.logFileName = newValue }
    }

    public var logLevel: UInt {
        get { storage.logLevel }
        set { storage.logLevel = newValue }
    }

    public var consoleLogLevel: UInt {
        get { storage.consoleLogLevel }
        set { storage.consoleLogLevel = newValue }
    }

    public var detectsVoiceActivity: Bool {
        get { storage.detectsVoiceActivity }
        set { storage.detectsVoiceActivity = newValue }
    }

    public var usesICE: Bool {
        get { storage.usesICE }
        set { storage.usesICE = newValue }
    }

    public var usesQoS: Bool {
        get { storage.usesQoS }
        set { storage.usesQoS = newValue }
    }

    public var transportPort: UInt {
        get { storage.transportPort }
        set {
            storage.transportPort =
                newValue <= 65_535 ? newValue : 0
        }
    }

    public var usesG711Only: Bool {
        get { storage.usesG711Only }
        set {
            guard storage.usesG711Only != newValue else {
                return
            }
            storage.usesG711Only = newValue
            updateCodecs()
        }
    }

    public var locksCodec: Bool {
        get { storage.locksCodec }
        set { storage.locksCodec = newValue }
    }

    public var parser: AKSIPURIParser {
        storage.parser!
    }

    public class func shared() -> AKSIPUserAgent {
        SIPUserAgentShared.instance
    }

    @objc(initWithDelegate:)
    public init(delegate: (any AKSIPUserAgentDelegate)?) {
        super.init()

        storage.detectedNATType = AKNATType(rawValue: 0)!
        storage.thread.qualityOfService = .userInitiated
        storage.thread.start()
        storage.parser = AKSIPURIParser(userAgent: self)

        self.delegate = delegate
    }

    public override convenience init() {
        self.init(delegate: nil)
    }

    deinit {
        if let delegate = storage.delegate {
            unsubscribe(delegate, from: self)
        }
        storage.shutdown()
    }

    public func start() {
        guard storage.state.rawValue == 0 else {
            return
        }

        guard pj_init() == 0 else {
            NSLog("Error initializing PJSIP")
            return
        }

        storage.state = AKSIPUserAgentState(rawValue: 1)!

        let request = SIPUserAgentStartRequest { [weak self] didStart in
            guard let self else { return }

            storage.state = AKSIPUserAgentState(
                rawValue: didStart ? 2 : 0
            )!

            NotificationCenter.default.post(
                name: .AKSIPUserAgentDidFinishStarting,
                object: self
            )
        }

        perform(
            #selector(threadStart(_:)),
            on: storage.thread,
            with: request,
            waitUntilDone: false
        )
    }

    public func stop() {
        guard storage.state.rawValue == 2 else {
            return
        }

        storage.state = AKSIPUserAgentState(rawValue: 3)!

        let request = SIPUserAgentStopRequest { [weak self] in
            self?.finishStopping()
        }

        perform(
            #selector(threadStop(_:)),
            on: storage.thread,
            with: request,
            waitUntilDone: false
        )
    }

    public func stopAndWait() {
        guard storage.state.rawValue == 2 else {
            return
        }

        storage.state = AKSIPUserAgentState(rawValue: 3)!

        perform(
            #selector(threadStopSynchronously),
            on: storage.thread,
            with: nil,
            waitUntilDone: true
        )
        finishStopping()
    }

    public func handleIPAddressChange() {
        guard storage.state.rawValue == 2 else {
            return
        }

        perform(
            #selector(threadHandleIPAddressChange),
            on: storage.thread,
            with: nil,
            waitUntilDone: false
        )
    }

    public func addAccount(
        _ account: AKSIPAccount,
        withPassword password: String
    ) -> Bool {
        if let delegate,
           delegate.responds(
            to: NSSelectorFromString("SIPUserAgentShouldAddAccount:")
           ),
           delegate.sipUserAgentShouldAddAccount?(account) == false
        {
            return false
        }

        var config = pjsua_acc_config()
        pjsua_acc_config_default(&config)

        let strings = PJSIPStringStorage()
        config.id = strings.make(account.uri.stringValue)
        config.reg_uri = strings.make(
            URI(
                address: account.registrar,
                transport: account.transport
            ).stringValue
        )

        let realm = account.realm.isEmpty ? "*" : account.realm
        TelephonePJSUAConfigureCredential(
            &config,
            strings.make(realm),
            strings.make(account.username),
            strings.make(password)
        )

        config.rtp_cfg.port = 4_000

        if usesQoS {
            config.rtp_cfg.qos_params.flags = PJ_QOS_PARAM_HAS_DSCP
            config.rtp_cfg.qos_params.dscp_val = 46
        }

        if !account.proxyHost.isEmpty {
            let proxy = account.proxyPort == 0
                ? URI(
                    host: account.proxyHost,
                    transport: account.transport
                )
                : URI(
                    host: account.proxyHost,
                    port: String(account.proxyPort),
                    transport: account.transport
                )

            TelephonePJSUASetAccountProxy(
                &config,
                strings.make(proxy.stringValue)
            )
        }

        config.reg_timeout = UInt32(account.reregistrationTime)

        let transport = transportIdentifier(for: account)
        guard transport >= 0 else {
            NSLog(
                "Could not create required SIP transport for account %@",
                account
            )
            return false
        }
        config.transport_id = transport

        config.use_srtp = account.transport == .tls
            ? PJMEDIA_SRTP_MANDATORY
            : PJMEDIA_SRTP_DISABLED
        config.ipv6_media_use = account.usesIPv6
            ? PJSUA_IPV6_ENABLED
            : PJSUA_IPV6_DISABLED

        config.allow_contact_rewrite =
            account.updatesContactHeader ? 1 : 0
        config.allow_via_rewrite =
            account.updatesViaHeader ? 1 : 0
        config.allow_sdp_nat_rewrite =
            account.updatesSDP ? 1 : 0
        config.lock_codec = locksCodec ? 1 : 0

        var identifier = pjsua_acc_id(-1)
        let status = pjsua_acc_add(
            &config,
            0,
            &identifier
        )
        guard status == 0 else {
            NSLog(
                "Error adding account %@ with status %d",
                account,
                status
            )
            return false
        }

        account.updateIdentifier(Int(identifier))
        account.thread = storage.thread
        storage.accounts.append(account)
        account.isOnline = true
        return true
    }

    public func removeAccount(_ account: AKSIPAccount) -> Bool {
        guard isStarted, account.identifier >= 0 else {
            return false
        }

        account.delegate?.sipAccountWillRemove(account)
        account.removeAllCalls()

        guard pjsua_acc_del(pjsua_acc_id(account.identifier)) == 0 else {
            return false
        }

        storage.accounts.removeAll { $0 === account }
        account.updateIdentifier(-1)
        return true
    }

    public func account(
        withIdentifier identifier: Int
    ) -> AKSIPAccount? {
        storage.accounts.first {
            $0.identifier == identifier
        }
    }

    public func call(
        withIdentifier identifier: Int
    ) -> AKSIPCall? {
        for account in storage.accounts {
            if let call = account.call(identifier: identifier) {
                return call
            }
        }
        return nil
    }

    public func hangUpAllCalls() {
        pjsua_call_hangup_all()
    }

    public func startRingback(for call: AKSIPCall) {
        guard storage.callData.indices.contains(call.identifier) else {
            return
        }

        let data = storage.callData.advanced(by: call.identifier)
        guard data.pointee.ringbackOn == 0 else {
            return
        }

        data.pointee.ringbackOn = 1
        storage.ringbackCount += 1

        if storage.ringbackCount == 1,
           storage.ringbackSlot >= 0
        {
            _ = pjsua_conf_connect(storage.ringbackSlot, 0)
        }
    }

    public func stopRingback(for call: AKSIPCall) {
        guard storage.callData.indices.contains(call.identifier) else {
            return
        }

        let data = storage.callData.advanced(by: call.identifier)
        guard data.pointee.ringbackOn != 0 else {
            return
        }

        data.pointee.ringbackOn = 0
        storage.ringbackCount = max(0, storage.ringbackCount - 1)

        if storage.ringbackCount == 0,
           storage.ringbackSlot >= 0
        {
            _ = pjsua_conf_disconnect(storage.ringbackSlot, 0)
            if let ringbackPort = storage.ringbackPort {
                _ = pjmedia_tonegen_rewind(ringbackPort)
            }
        }
    }

    public func setSoundInputDevice(
        _ input: Int,
        soundOutputDevice output: Int
    ) -> Bool {
        guard isStarted else {
            return false
        }

        let capture = input >= 0
            ? Int32(input)
            : Int32(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV)
        let playback = output >= 0
            ? Int32(output)
            : Int32(PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV)

        return pjsua_set_snd_dev(capture, playback) == 0
    }

    public func stopSound() -> Bool {
        isStarted && pjsua_set_null_snd_dev() == 0
    }

    public func updateAudioDevices() {
        guard isStarted else {
            return
        }

        _ = pjsua_set_null_snd_dev()
        _ = pjmedia_snd_deinit()
        _ = pjmedia_snd_init(pjsua_get_pool_factory())
    }

    public func string(
        forSIPResponseCode responseCode: Int
    ) -> String {
        SIPResponseLocalization.localizedString(
            for: responseCode
        ) ?? "Response code: \(responseCode)"
    }

    @objc
    private final func threadStart(
        _ request: SIPUserAgentStartRequest
    ) {
        autoreleasepool {
            let didStart = startPJSIPRuntime()
            DispatchQueue.main.async {
                request.completion(didStart)
            }
        }
    }

    @objc
    private final func threadHandleIPAddressChange() {
        autoreleasepool {
            guard TelephonePJSIPRegisterCurrentThread() == 0 else {
                return
            }

            var parameters = pjsua_ip_change_param()
            pjsua_ip_change_param_default(&parameters)

            let status = pjsua_handle_ip_change(&parameters)
            if status != 0 {
                NSLog(
                    "Error handling SIP IP address change: %d",
                    status
                )
            }
        }
    }

    @objc
    private final func threadStop(
        _ request: SIPUserAgentStopRequest
    ) {
        autoreleasepool {
            stopPJSIPRuntime()
            DispatchQueue.main.async {
                request.completion()
            }
        }
    }

    @objc
    private final func threadStopSynchronously() {
        autoreleasepool {
            stopPJSIPRuntime()
        }
    }

    @nonobjc
    private final func startPJSIPRuntime() -> Bool {
        guard TelephonePJSIPRegisterCurrentThread() == 0 else {
            NSLog("Error registering PJSIP control thread")
            return false
        }

        guard pjsua_create() == 0 else {
            NSLog("Error creating PJSUA")
            return false
        }

        storage.pool = pjsua_pool_create(
            "AKSIPUserAgent",
            4_000,
            1_000
        )
        guard storage.pool != nil else {
            NSLog("Could not create memory pool")
            stopPJSIPRuntime()
            return false
        }

        var userAgentConfig = pjsua_config()
        var loggingConfig = pjsua_logging_config()
        var mediaConfig = pjsua_media_config()
        var transportConfig = pjsua_transport_config()

        pjsua_config_default(&userAgentConfig)
        pjsua_logging_config_default(&loggingConfig)
        pjsua_media_config_default(&mediaConfig)
        pjsua_transport_config_default(&transportConfig)

        let strings = PJSIPStringStorage()

        userAgentConfig.max_calls = UInt32(maxCalls)
        userAgentConfig.use_timer = PJSUA_SIP_TIMER_INACTIVE

        if !nameServers.isEmpty {
            userAgentConfig.nameserver_count = UInt32(nameServers.count)
            for (index, nameServer) in nameServers.enumerated() {
                TelephonePJSUASetNameServer(
                    &userAgentConfig,
                    UInt32(index),
                    strings.make(nameServer)
                )
            }
        }

        if !outboundProxyHost.isEmpty {
            userAgentConfig.outbound_proxy_cnt = 1
            let proxy = outboundProxyPort == 5_060
                ? URI(host: outboundProxyHost, transport: .udp)
                : URI(
                    host: outboundProxyHost,
                    port: String(outboundProxyPort),
                    transport: .udp
                )
            TelephonePJSUASetOutboundProxy(
                &userAgentConfig,
                strings.make(proxy.stringValue)
            )
        }

        if !STUNServerHost.isEmpty {
            userAgentConfig.stun_srv_cnt = 1
            let server = STUNServerPort == 3_478
                ? ServiceAddress(host: STUNServerHost)
                : ServiceAddress(
                    host: STUNServerHost,
                    port: String(STUNServerPort)
                )
            TelephonePJSUASetSTUNServer(
                &userAgentConfig,
                strings.make(server.stringValue)
            )
        }

        userAgentConfig.stun_try_ipv6 = 1
        userAgentConfig.user_agent = strings.make(userAgentString)

        if !logFileName.isEmpty {
            loggingConfig.log_filename = strings.make(
                (logFileName as NSString).expandingTildeInPath
            )
        }

        loggingConfig.level = UInt32(logLevel)
        loggingConfig.console_level = UInt32(consoleLogLevel)

        mediaConfig.no_vad = detectsVoiceActivity ? 0 : 1
        mediaConfig.enable_ice = usesICE ? 1 : 0
        mediaConfig.snd_auto_close_time = 1
        mediaConfig.ec_options = UInt32(PJMEDIA_ECHO_USE_SW_ECHO)

        if usesQoS {
            transportConfig.qos_params.flags = PJ_QOS_PARAM_HAS_DSCP
            transportConfig.qos_params.dscp_val = 24
        }

        transportConfig.port = UInt32(transportPort)
        TelephonePJSUAConfigureCallbacks(&userAgentConfig)

        guard pjsua_init(
            &userAgentConfig,
            &loggingConfig,
            &mediaConfig
        ) == 0 else {
            NSLog("Error initializing PJSUA")
            stopPJSIPRuntime()
            return false
        }

        guard createRingback(mediaConfig: mediaConfig) else {
            stopPJSIPRuntime()
            return false
        }

        var udpIdentifier = pjsua_transport_id(-1)
        guard pjsua_transport_create(
            PJSIP_TRANSPORT_UDP,
            &transportConfig,
            &udpIdentifier
        ) == 0 else {
            NSLog("Error creating UDP4 transport")
            stopPJSIPRuntime()
            return false
        }

        storage.udp4Transport = udpIdentifier

        if transportPort == 0 {
            var info = pjsua_transport_info()
            if pjsua_transport_get_info(
                udpIdentifier,
                &info
            ) == 0 {
                transportPort = UInt(info.local_name.port)
            }
        }

        updateCodecs()

        guard pjsua_start() == 0 else {
            NSLog("Error starting PJSUA")
            stopPJSIPRuntime()
            return false
        }

        return true
    }

    @nonobjc
    private final func createRingback(
        mediaConfig: pjsua_media_config
    ) -> Bool {
        guard let pool = storage.pool else {
            return false
        }

        let samplesPerFrame =
            mediaConfig.audio_frame_ptime
            * mediaConfig.clock_rate
            * mediaConfig.channel_count
            / 1_000

        let strings = PJSIPStringStorage()
        var name = strings.make("ringback")
        var port: OpaquePointer?

        guard pjmedia_tonegen_create2(
            pool,
            &name,
            mediaConfig.clock_rate,
            mediaConfig.channel_count,
            samplesPerFrame,
            16,
            UInt32(PJMEDIA_TONEGEN_LOOP),
            &port
        ) == 0, let port else {
            NSLog("Error creating ringback tones")
            return false
        }

        storage.ringbackPort = port

        var tone = pjmedia_tone_desc()
        tone.freq1 = 440
        tone.freq2 = 480
        tone.on_msec = 2_000
        tone.off_msec = 4_000

        guard pjmedia_tonegen_play(
            port,
            1,
            &tone,
            UInt32(PJMEDIA_TONEGEN_LOOP)
        ) == 0 else {
            NSLog("Error configuring ringback tone")
            return false
        }

        var slot = pjsua_conf_port_id(-1)
        guard pjsua_conf_add_port(
            pool,
            port,
            &slot
        ) == 0 else {
            NSLog("Error adding media port for ringback tones")
            return false
        }

        storage.ringbackSlot = slot
        return true
    }

    @nonobjc
    private final func stopPJSIPRuntime() {
        if let port = storage.ringbackPort {
            if storage.ringbackSlot >= 0 {
                _ = pjsua_conf_remove_port(storage.ringbackSlot)
            }
            storage.ringbackSlot = -1
            _ = pjmedia_port_destroy(port)
            storage.ringbackPort = nil
        }

        storage.resetTransportIdentifiers()

        if let pool = storage.pool {
            pj_pool_release(pool)
            storage.pool = nil
        }

        if pjsua_destroy() != 0 {
            NSLog("Error stopping SIP user agent")
        }
    }

    @nonobjc
    private final func finishStopping() {
        pj_shutdown()
        storage.accounts.removeAll()
        storage.state = AKSIPUserAgentState(rawValue: 0)!

        NotificationCenter.default.post(
            name: .AKSIPUserAgentDidFinishStopping,
            object: self
        )
    }

    @nonobjc
    private final func transportIdentifier(
        for account: AKSIPAccount
    ) -> pjsua_transport_id {
        switch account.transport {
        case .udp:
            if !account.usesIPv6 {
                return storage.udp4Transport
            }
            if storage.udp6Transport < 0 {
                storage.udp6Transport = createSIPTransport(
                    PJSIP_TRANSPORT_UDP6,
                    name: "UDP6",
                    isTLS: false
                )
            }
            return storage.udp6Transport

        case .tcp:
            if account.usesIPv6 {
                if storage.tcp6Transport < 0 {
                    storage.tcp6Transport = createSIPTransport(
                        PJSIP_TRANSPORT_TCP6,
                        name: "TCP6",
                        isTLS: false
                    )
                }
                return storage.tcp6Transport
            }
            if storage.tcp4Transport < 0 {
                storage.tcp4Transport = createSIPTransport(
                    PJSIP_TRANSPORT_TCP,
                    name: "TCP4",
                    isTLS: false
                )
            }
            return storage.tcp4Transport

        case .tls:
            if account.usesIPv6 {
                if storage.tls6Transport < 0 {
                    storage.tls6Transport = createSIPTransport(
                        PJSIP_TRANSPORT_TLS6,
                        name: "TLS6",
                        isTLS: true
                    )
                }
                return storage.tls6Transport
            }
            if storage.tls4Transport < 0 {
                storage.tls4Transport = createSIPTransport(
                    PJSIP_TRANSPORT_TLS,
                    name: "TLS4",
                    isTLS: true
                )
            }
            return storage.tls4Transport
        }
    }

    @nonobjc
    private final func createSIPTransport(
        _ type: pjsip_transport_type_e,
        name: String,
        isTLS: Bool
    ) -> pjsua_transport_id {
        var config = pjsua_transport_config()
        pjsua_transport_config_default(&config)

        if usesQoS {
            config.qos_params.flags = PJ_QOS_PARAM_HAS_DSCP
            config.qos_params.dscp_val = 24
        }

        let strings = PJSIPStringStorage()

        if isTLS {
            config.tls_setting.verify_server = 1
            config.tls_setting.verify_client = 1

            if let certificate = Bundle.main.url(
                forResource: "PublicCAs",
                withExtension: "pem"
            ) {
                config.tls_setting.ca_list_file =
                    strings.make(certificate.path)
            }

            config.port =
                transportPort > 0 && transportPort < 65_535
                    ? UInt32(transportPort + 1)
                    : 0
        } else {
            config.port = UInt32(transportPort)
        }

        var identifier = pjsua_transport_id(-1)
        let status = pjsua_transport_create(
            type,
            &config,
            &identifier
        )
        guard status == 0 else {
            NSLog(
                "Error creating %@ SIP transport: %d",
                name,
                status
            )
            return -1
        }

        var info = pjsua_transport_info()
        if pjsua_transport_get_info(identifier, &info) == 0 {
            NSLog(
                "SIP transport %@ listening on port %u",
                name,
                info.local_name.port
            )
        }

        return identifier
    }

    @nonobjc
    private final func updateCodecs() {
        guard
            storage.state.rawValue != 0,
            storage.state.rawValue != 3
        else {
            return
        }

        let capacity = 64
        let codecs = UnsafeMutablePointer<pjsua_codec_info>.allocate(
            capacity: capacity
        )
        defer { codecs.deallocate() }

        var count = UInt32(capacity)
        guard pjsua_enum_codecs(codecs, &count) == 0 else {
            NSLog("Error getting list of codecs")
            return
        }

        for index in 0..<Int(count) {
            var identifier = codecs[index].codec_id
            let name = string(from: identifier)
            let defaultPriority = codecPriority(for: name)
            let priority: UInt8

            if usesG711Only {
                priority =
                    name == "PCMU/8000/1"
                    || name == "PCMA/8000/1"
                        ? defaultPriority
                        : 0
            } else {
                priority = defaultPriority
            }

            if pjsua_codec_set_priority(
                &identifier,
                priority
            ) != 0 {
                NSLog("Error setting codec priority for %@", name)
            }
        }
    }
}

extension AKSIPUserAgent: @unchecked Sendable {}

private enum SIPUserAgentShared {
    static let instance = AKSIPUserAgent(delegate: nil)
}

private final class SIPUserAgentStorage {
    weak var delegate: (any AKSIPUserAgentDelegate)?

    var state = AKSIPUserAgentState(rawValue: 0)!
    var detectedNATType = AKNATType(rawValue: 0)!

    var maxCalls = 0
    var nameServers: [String] = []
    var outboundProxyHost = ""
    var outboundProxyPort: UInt = 5_060
    var stunServerHost = ""
    var stunServerPort: UInt = 3_478
    var userAgentString = ""
    var logFileName = ""
    var logLevel: UInt = 3
    var consoleLogLevel: UInt = 0
    var detectsVoiceActivity = true
    var usesICE = false
    var usesQoS = true
    var transportPort: UInt = 0
    var usesG711Only = false
    var locksCodec = true

    var parser: AKSIPURIParser?
    var accounts: [AKSIPAccount] = []

    let thread = WaitingThread()

    var pool: OpaquePointer?
    var ringbackSlot = pjsua_conf_port_id(-1)
    var ringbackPort: OpaquePointer?
    var ringbackCount = 0

    var udp4Transport = pjsua_transport_id(-1)
    var udp6Transport = pjsua_transport_id(-1)
    var tcp4Transport = pjsua_transport_id(-1)
    var tcp6Transport = pjsua_transport_id(-1)
    var tls4Transport = pjsua_transport_id(-1)
    var tls6Transport = pjsua_transport_id(-1)

    let callData:
        UnsafeMutablePointer<AKSIPUserAgentCallData>

    init() {
        let count = Int(PJSUA_MAX_CALLS)
        callData = .allocate(capacity: count)
        callData.initialize(
            repeating: AKSIPUserAgentCallData(),
            count: count
        )
    }

    func resetTransportIdentifiers() {
        udp4Transport = -1
        udp6Transport = -1
        tcp4Transport = -1
        tcp6Transport = -1
        tls4Transport = -1
        tls6Transport = -1
    }

    func shutdown() {
        let count = Int(PJSUA_MAX_CALLS)
        callData.deinitialize(count: count)
        callData.deallocate()
    }
}

private extension UnsafeMutablePointer
where Pointee == AKSIPUserAgentCallData {
    var indices: Range<Int> {
        0..<Int(PJSUA_MAX_CALLS)
    }
}

private final class SIPUserAgentStartRequest:
    NSObject,
    @unchecked Sendable
{
    let completion: @MainActor @Sendable (Bool) -> Void

    init(
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.completion = completion
    }
}

private final class SIPUserAgentStopRequest:
    NSObject,
    @unchecked Sendable
{
    let completion: @MainActor @Sendable () -> Void

    init(
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        self.completion = completion
    }
}

private final class PJSIPStringStorage {
    private var pointers: [UnsafeMutablePointer<CChar>] = []

    func make(_ value: String) -> pj_str_t {
        let bytes = Array(value.utf8CString)
        let pointer = UnsafeMutablePointer<CChar>.allocate(
            capacity: bytes.count
        )
        pointer.initialize(from: bytes, count: bytes.count)
        pointers.append(pointer)
        return pj_str(pointer)
    }

    deinit {
        for pointer in pointers {
            pointer.deallocate()
        }
    }
}

private func codecPriority(for identifier: String) -> UInt8 {
    switch identifier {
    case "opus/48000/2":
        130
    case "G722/16000/1":
        129
    case "PCMA/8000/1":
        128
    case "PCMU/8000/1":
        127
    default:
        0
    }
}

private let userAgentDelegateSubscriptions:
    [(Selector, Notification.Name)] = [
        (
            NSSelectorFromString("SIPUserAgentDidFinishStarting:"),
            .AKSIPUserAgentDidFinishStarting
        ),
        (
            NSSelectorFromString("SIPUserAgentDidFinishStopping:"),
            .AKSIPUserAgentDidFinishStopping
        ),
        (
            NSSelectorFromString("SIPUserAgentDidDetectNAT:"),
            .AKSIPUserAgentDidDetectNAT
        ),
    ]

private func subscribe(
    _ delegate: AKSIPUserAgentDelegate,
    to agent: AKSIPUserAgent
) {
    let center = NotificationCenter.default

    for (selector, name) in userAgentDelegateSubscriptions
    where delegate.responds(to: selector) {
        center.addObserver(
            delegate,
            selector: selector,
            name: name,
            object: agent
        )
    }
}

private func unsubscribe(
    _ delegate: AKSIPUserAgentDelegate,
    from agent: AKSIPUserAgent
) {
    NotificationCenter.default.removeObserver(
        delegate,
        name: nil,
        object: agent
    )
}
