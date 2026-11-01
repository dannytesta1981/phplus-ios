import UIKit
import WebKit
import AVFAudio
import MediaPlayer

@MainActor protocol PrivacyMediaParticipant: AnyObject {
    func suspendCapture()
    func resumeMediaIfAllowed()
}
@MainActor final class MediaPrivacyHub {
    static let shared = MediaPrivacyHub()
    private let participants = NSHashTable<AnyObject>.weakObjects()
    func register(_ participant: PrivacyMediaParticipant) { participants.add(participant) }
    func suspendAll() {
        for object in participants.allObjects { (object as? PrivacyMediaParticipant)?.suspendCapture() }
        clearOwnSystemMedia()
    }
    func resumeVisible() {
        for object in participants.allObjects { (object as? PrivacyMediaParticipant)?.resumeMediaIfAllowed() }
    }
    func clearOwnSystemMedia() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Do not activate playback categories/background audio just to clear metadata.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor final class PrivacyCurtain {
    private(set) var curtains: [ObjectIdentifier: UIWindow] = [:]
    func hide(in scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        if let existing = curtains[key] { existing.isHidden = false; return }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        let controller = UIViewController()
        controller.view.backgroundColor = UIColor(white: 0.10, alpha: 1)
        let label = UILabel(); label.text = "phplus"; label.textColor = .secondaryLabel
        label.textAlignment = .center; label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor), label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)])
        window.rootViewController = controller
        window.isUserInteractionEnabled = false
        window.isHidden = false
        curtains[key] = window
    }
    func reveal(in scene: UIWindowScene) { curtains.removeValue(forKey: ObjectIdentifier(scene))?.isHidden = true }
}
