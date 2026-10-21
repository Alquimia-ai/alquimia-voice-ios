/// Everything that touches `AVAudioEngine`, the player node or the converter runs here.
@globalActor
actor AudioActor {
    static let shared = AudioActor()
}
