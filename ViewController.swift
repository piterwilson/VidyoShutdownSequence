import Cocoa

class ViewController: NSViewController {
    
    private(set) var vidyoConnector: VCConnector?
    
    @IBOutlet var videoView: NSView!
    
    @IBOutlet weak var connectBtn: NSButton!
    @IBOutlet weak var connectionSpinner: NSProgressIndicator!
    @IBOutlet weak var connectionState: NSTextField!
    
    private var isConnected = false
    
    private var shutDownInfo: (shutDown: Bool, close: Bool) = (shutDown: false, close: false)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        VCConnectorPkg.vcInitialize()
        
        vidyoConnector = VCConnector(UnsafeMutableRawPointer(&videoView),
                                     viewStyle: .default,
                                     remoteParticipants: 4,
                                     logFileFilter: "",
                                     logFileName: "",
                                     userData: 0)
        
        subscribeToEvents()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        self.view.window?.delegate = self
        
        refreshRenderer()
        updateUI(status: "Ready")
    }
    
    @IBAction func shutDownClient(_ sender: Any) {
        let _ = attemptShutDownClient()
    }
    
    @IBAction func connectAction(_ sender: Any) {
        let config = VidyoClientConfig(host: "prod.vidyo.io", displayName: "Mac User", resourceID: "demoRoom")
        let token = "cHJvdmlzaW9uAHVzZXIxQDg3MTFlMC52aWR5by5pbwA2Mzc0Njg0MjQ0NwAAY2YzMDM2NDA1YWYyNjU3M2FjYjBjNzY0NDBlZDQ4Y2I1ZTVkZTEyOWQwOWE3MTBhMzYyNmZiZTdiYzJmZTEyMmU2NzNmODA2YTM3MTUxMjFkNDcyMmI3YjgwMGE3NWM5"
        
        toggleConnect(using: config, token: token)
    }
    
    private func toggleConnect(using config: VidyoClientConfig, token: String) {
        guard let connector = vidyoConnector else { return; }
        
        refreshRenderer()
        
        self.connectionSpinner.isHidden = false
        self.updateUI(status: isConnected ? "Disconnecting..." : "Connecting...", hideSpinnder: false)
        
        if isConnected {
            connector.disconnect()
        } else {
            connector.connect(config.host, token: token, displayName: config.displayName, resourceId: config.resourceID, connectorIConnect: self)
        }
    }
    
    private func refreshRenderer() {
        DispatchQueue.main.async {
            [weak self] in
            guard let this = self else { fatalError("Can't maintain self reference."); }
            
            this.vidyoConnector?.showView(at: UnsafeMutableRawPointer(&this.videoView),
                                          x: 0, y: 0,
                                          width: UInt32(this.videoView.frame.size.width),
                                          height: UInt32(this.videoView.frame.size.height))
        }
    }
    
    private func updateUI(status: String?, hideSpinnder: Bool = true) {
        DispatchQueue.main.async(execute: {
            [weak self] in
            guard let this = self else { fatalError("Can't maintain self reference."); }
            
            this.connectBtn.title = this.isConnected ? "Disconnect" : "Connect"
            this.connectionState.stringValue = status ?? ""
            
            this.connectionSpinner.isHidden = hideSpinnder
            this.connectionSpinner.startAnimation(nil)
        })
    }
    
    private func attemptShutDownClient() -> Bool {
        if let connector = vidyoConnector {
            DispatchQueue.main.async {
                [weak self] in
                guard let this = self else { fatalError("Can't maintain self reference."); }
                
                this.connectBtn.isEnabled = false
                this.connectBtn.alphaValue = 0.3
                this.connectBtn.title = "..."
            }
            
            let state = connector.getState()
            
            // Allow shut down only in disconnected state
            if state == .idle || state == .ready {
                shutdownVidyo()
                
                DispatchQueue.main.async {
                    [weak self] in
                    guard let this = self else { fatalError("Can't maintain self reference."); }
                    if this.shutDownInfo.close { this.view.window?.close(); }
                }
                
                return true
            } else {
                self.shutDownInfo.shutDown = true
                
                DispatchQueue.main.async {
                    [weak self] in
                    guard let this = self else { fatalError("Can't maintain self reference."); }
                    
                    this.updateUI(status: "Disconnecting...", hideSpinnder: false)
                    this.vidyoConnector?.disconnect()
                }
                
                return false
            }
        }
        
        return true
    }
    
    private func shutdownVidyo() {
        DispatchQueue(label: "shutdown", qos: .background).async {
            [weak self] in
            guard let this = self else { fatalError("Can't maintain self reference."); }
            
            this.unsubscribeFromEvents()
            
            this.vidyoConnector?.select(nil as VCLocalCamera?)
            this.vidyoConnector?.select(nil as VCLocalMicrophone?)
            this.vidyoConnector?.select(nil as VCLocalSpeaker?)
            
            this.vidyoConnector?.disable()
            this.vidyoConnector = nil
            
            VCConnectorPkg.uninitialize()
        }
    }
    
    private func subscribeToEvents() {
        let eventListener = VidyoEventListener()
        
        vidyoConnector?.registerParticipantEventListener(eventListener)
        
        vidyoConnector?.registerLocalCameraEventListener(eventListener)
        vidyoConnector?.registerLocalMicrophoneEventListener(eventListener)
        vidyoConnector?.registerLocalSpeakerEventListener(eventListener)
        
        vidyoConnector?.registerRemoteCameraEventListener(eventListener)
        vidyoConnector?.registerRemoteMicrophoneEventListener(eventListener)
        
        vidyoConnector?.registerMessageEventListener(eventListener)
        vidyoConnector?.registerResourceManagerEventListener(eventListener)
    }
    
    func unsubscribeFromEvents() {
        vidyoConnector?.unregisterParticipantEventListener()
        
        vidyoConnector?.unregisterLocalCameraEventListener()
        vidyoConnector?.unregisterLocalMicrophoneEventListener()
        vidyoConnector?.unregisterLocalSpeakerEventListener()
        
        vidyoConnector?.unregisterRemoteCameraEventListener()
        vidyoConnector?.unregisterRemoteMicrophoneEventListener()
        
        vidyoConnector?.unregisterMessageEventListener()
        vidyoConnector?.unregisterResourceManagerEventListener()
    }
}

extension ViewController: NSWindowDelegate  {
    
    func windowDidEndLiveResize(_ notification: Notification) {
        refreshRenderer()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shutDownInfo.close = true
        return attemptShutDownClient()
    }
}

extension ViewController: VCConnectorIConnect {
    
    func onSuccess() {
        isConnected = true
        updateUI(status: "Connected")
    }
    
    func onFailure(_ reason: VCConnectorFailReason) {
        isConnected = false
        updateUI(status: "Failed")
    }
    
    func onDisconnected(_ reason: VCConnectorDisconnectReason) {
        isConnected = false
        updateUI(status: "Disconnected")
        
        if self.shutDownInfo.shutDown {
            let _ = attemptShutDownClient()
        }
    }
}

/// Config object for initiating Vidyo connection
public struct VidyoClientConfig {
    /// Host address (e.g. `prod.vidyo.io`)
    public let host: String
    /// Vidyo token (obtained from `VidyoService`)
    public let displayName: String
    public let resourceID: String
    
    public init(host: String, displayName: String, resourceID: String) {
        self.host = host
        self.displayName = displayName
        self.resourceID = resourceID
    }
}

protocol VidyoEventListenerProtocol: class,
VCConnectorIRegisterParticipantEventListener, VCConnectorIRegisterLocalCameraEventListener, VCConnectorIRegisterLocalMicrophoneEventListener, VCConnectorIRegisterLocalSpeakerEventListener, VCConnectorIRegisterRemoteCameraEventListener, VCConnectorIRegisterRemoteMicrophoneEventListener, VCConnectorIRegisterRemoteCameraFrameListener, VCConnectorIRegisterRemoteMicrophoneFrameListener, VCConnectorIRegisterMessageEventListener, VCConnectorIRegisterResourceManagerEventListener { }

class VidyoEventListener: VidyoEventListenerProtocol {
    weak var delegate: VidyoEventListenerProtocol?
}

extension VidyoEventListener: VCConnectorIRegisterParticipantEventListener {
    func onParticipantJoined(_ participant: VCParticipant!) {
        delegate?.onParticipantJoined(participant)
    }
    
    func onParticipantLeft(_ participant: VCParticipant!) {
        delegate?.onParticipantLeft(participant)
    }
    
    func onDynamicParticipantChanged(_ participants: NSMutableArray!) {
        delegate?.onDynamicParticipantChanged(participants)
    }
    
    func onLoudestParticipantChanged(_ participant: VCParticipant!, audioOnly: Bool) {
        delegate?.onLoudestParticipantChanged(participant, audioOnly: audioOnly)
    }
}

extension VidyoEventListener: VCConnectorIRegisterLocalCameraEventListener {
    func onLocalCameraAdded(_ localCamera: VCLocalCamera!) {
        delegate?.onLocalCameraAdded(localCamera)
    }
    
    func onLocalCameraRemoved(_ localCamera: VCLocalCamera!) {
        delegate?.onLocalCameraRemoved(localCamera)
    }
    
    func onLocalCameraSelected(_ localCamera: VCLocalCamera!) {
        delegate?.onLocalCameraSelected(localCamera)
    }
    
    func onLocalCameraStateUpdated(_ localCamera: VCLocalCamera!, state: VCDeviceState) {
        delegate?.onLocalCameraStateUpdated(localCamera, state: state)
    }
}

extension VidyoEventListener: VCConnectorIRegisterLocalMicrophoneEventListener {
    func onLocalMicrophoneAdded(_ localMicrophone: VCLocalMicrophone!) {
        delegate?.onLocalMicrophoneAdded(localMicrophone)
    }
    
    func onLocalMicrophoneRemoved(_ localMicrophone: VCLocalMicrophone!) {
        delegate?.onLocalMicrophoneRemoved(localMicrophone)
    }
    
    func onLocalMicrophoneSelected(_ localMicrophone: VCLocalMicrophone!) {
        delegate?.onLocalMicrophoneSelected(localMicrophone)
    }
    
    func onLocalMicrophoneStateUpdated(_ localMicrophone: VCLocalMicrophone!, state: VCDeviceState) {
        delegate?.onLocalMicrophoneStateUpdated(localMicrophone, state: state)
    }
}

extension VidyoEventListener: VCConnectorIRegisterLocalSpeakerEventListener {
    func onLocalSpeakerAdded(_ localSpeaker: VCLocalSpeaker!) {
        delegate?.onLocalSpeakerAdded(localSpeaker)
    }
    
    func onLocalSpeakerRemoved(_ localSpeaker: VCLocalSpeaker!) {
        delegate?.onLocalSpeakerRemoved(localSpeaker)
    }
    
    func onLocalSpeakerSelected(_ localSpeaker: VCLocalSpeaker!) {
        delegate?.onLocalSpeakerSelected(localSpeaker)
    }
    
    func onLocalSpeakerStateUpdated(_ localSpeaker: VCLocalSpeaker!, state: VCDeviceState) {
        delegate?.onLocalSpeakerStateUpdated(localSpeaker, state: state)
    }
}

extension VidyoEventListener: VCConnectorIRegisterRemoteCameraEventListener {
    func onRemoteCameraAdded(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!) {
        delegate?.onRemoteCameraAdded(remoteCamera, participant: participant)
    }
    
    func onRemoteCameraRemoved(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!) {
        delegate?.onRemoteCameraRemoved(remoteCamera, participant: participant)
    }
    
    func onRemoteCameraStateUpdated(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!, state: VCDeviceState) {
        delegate?.onRemoteCameraStateUpdated(remoteCamera, participant: participant, state: state)
    }
}

extension VidyoEventListener: VCConnectorIRegisterRemoteMicrophoneEventListener {
    func onRemoteMicrophoneAdded(_ remoteMicrophone: VCRemoteMicrophone!, participant: VCParticipant!) {
        delegate?.onRemoteMicrophoneAdded(remoteMicrophone, participant: participant)
    }
    
    func onRemoteMicrophoneRemoved(_ remoteMicrophone: VCRemoteMicrophone!, participant: VCParticipant!) {
        delegate?.onRemoteMicrophoneRemoved(remoteMicrophone, participant: participant)
    }
    
    func onRemoteMicrophoneStateUpdated(_ remoteMicrophone: VCRemoteMicrophone!, participant: VCParticipant!, state: VCDeviceState) {
        delegate?.onRemoteMicrophoneStateUpdated(remoteMicrophone, participant: participant, state: state)
    }
}

extension VidyoEventListener: VCConnectorIRegisterRemoteCameraFrameListener {
    func onRemoteCameraFrame(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!, videoFrame: VCVideoFrame!) {
        delegate?.onRemoteCameraFrame(remoteCamera, participant: participant, videoFrame: videoFrame)
    }
}

extension VidyoEventListener: VCConnectorIRegisterRemoteMicrophoneFrameListener {
    func onRemoteMicrophoneFrame(_ remoteMicrophone: VCRemoteMicrophone!, participant: VCParticipant!, audioFrame: VCAudioFrame!) {
        delegate?.onRemoteMicrophoneFrame(remoteMicrophone, participant: participant, audioFrame: audioFrame)
    }
}

extension VidyoEventListener: VCConnectorIRegisterMessageEventListener {
    func onChatMessageReceived(_ participant: VCParticipant!, chatMessage: VCChatMessage!) {
        delegate?.onChatMessageReceived(participant, chatMessage: chatMessage)
    }
}

extension VidyoEventListener: VCConnectorIRegisterResourceManagerEventListener {
    func onAvailableResourcesChanged(_ cpuEncode: UInt32, cpuDecode: UInt32, bandwidthSend: UInt32, bandwidthReceive: UInt32) {
        delegate?.onAvailableResourcesChanged(cpuEncode, cpuDecode: cpuDecode, bandwidthSend: bandwidthSend, bandwidthReceive: bandwidthReceive)
    }
    
    func onMaxRemoteSourcesChanged(_ maxRemoteSources: UInt32) {
        delegate?.onMaxRemoteSourcesChanged(maxRemoteSources)
    }
}

class VCConnectorIConnectHandler: VCConnectorIConnect {
    weak var delegate: VCConnectorIConnect?
    func onSuccess() {
        delegate?.onSuccess()
    }
    
    func onFailure(_ reason: VCConnectorFailReason) {
        delegate?.onFailure(reason)
    }
    
    func onDisconnected(_ reason: VCConnectorDisconnectReason) {
        delegate?.onDisconnected(reason)
    }
}

class VidyoLocalCameraFrameListener: VCConnectorIRegisterLocalCameraFrameListener {
    weak var delegate: VCConnectorIRegisterLocalCameraFrameListener?
    func onLocalCameraFrame(_ localCamera: VCLocalCamera!, videoFrame: VCVideoFrame!) {
        delegate?.onLocalCameraFrame(localCamera, videoFrame: videoFrame)
    }
}

class VidyoLocalMicrophoneFrameListener: VCConnectorIRegisterLocalMicrophoneFrameListener {
    weak var delegate: VCConnectorIRegisterLocalMicrophoneFrameListener?
    func onLocalMicrophoneFrame(_ localMicrophone: VCLocalMicrophone!, audioFrame: VCAudioFrame!) {
        delegate?.onLocalMicrophoneFrame(localMicrophone, audioFrame: audioFrame)
    }
}

class VidyoRemoteCameraFrameListener: VCConnectorIRegisterRemoteCameraFrameListener {
    weak var delegate: VCConnectorIRegisterRemoteCameraFrameListener?
    func onRemoteCameraFrame(_ remoteCamera: VCRemoteCamera!, participant: VCParticipant!, videoFrame: VCVideoFrame!) {
        delegate?.onRemoteCameraFrame(remoteCamera, participant: participant, videoFrame: videoFrame)
    }
}

class VidyoRemoteMicrophoneFrameListener: VCConnectorIRegisterRemoteMicrophoneFrameListener {
    weak var delegate: VCConnectorIRegisterRemoteMicrophoneFrameListener?
    func onRemoteMicrophoneFrame(_ remoteMicrophone: VCRemoteMicrophone!, participant: VCParticipant!, audioFrame: VCAudioFrame!) {
        delegate?.onRemoteMicrophoneFrame(remoteMicrophone, participant: participant, audioFrame: audioFrame)
    }
}
