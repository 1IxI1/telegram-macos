import Cocoa
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public enum SoundEffect {
    case quizCorrect
    case quizIncorrect
    case confetti
    case sent
    public var name: String {
        switch self {
        case .quizCorrect:
            return "quiz-correct"
        case .quizIncorrect:
            return "quiz-incorrect"
        case .confetti:
            return "confetti"
        case .sent:
            return "sent"
        }
    }
    public var ext: String {
        switch self {
        case .quizCorrect, .quizIncorrect, .confetti, .sent:
            return "mp3"
        }
    }
}


public func playSoundEffect(_ sound: SoundEffect) {
    let afterSentSound:NSSound? = {
        
        let p = Bundle.main.path(forResource: sound.name, ofType: sound.ext)
        var sound:NSSound?
        if let p = p {
            sound = NSSound(contentsOfFile: p, byReference: true)
            sound?.volume = 0.1
        }
        
        return sound
    }()
    afterSentSound?.play()
}
