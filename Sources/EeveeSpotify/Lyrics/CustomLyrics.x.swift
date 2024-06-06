import Orion
import SwiftUI

class SPTPlayerTrackHook: ClassHook<NSObject> {

    static let targetName = "SPTPlayerTrack"

    func setMetadata(_ metadata: [String:String]) {
        var meta = metadata

        meta["has_lyrics"] = "true"
        orig.setMetadata(meta)
    }
}

class EncoreButtonHook: ClassHook<UIButton> {

    static let targetName = "_TtC12EncoreMobileP33_6EF3A3C098E69FB1E331877B69ACBF8512EncoreButton"

    func intrinsicContentSize() -> CGSize {

        if target.accessibilityIdentifier == "Components.UI.LyricsHeader.ReportButton", 
            UserDefaults.lyricsSource != .musixmatch {
            target.isEnabled = false
        }

        return orig.intrinsicContentSize()
    }
}

func getCurrentTrackLyricsData(originalLyrics: Lyrics? = nil) throws -> Data {

    guard let track = HookedInstances.currentTrack else {
        throw LyricsError.NoCurrentTrack
    }

    var source = UserDefaults.lyricsSource

    let plainLyrics: PlainLyrics?

    do {
        plainLyrics = try LyricsRepository.getLyrics(
            title: track.trackTitle(), 
            artist: track.artistTitle(), 
            spotifyTrackId: track.URI().spt_trackIdentifier(),
            source: source
        )
    }

    catch let error as LyricsError {
        
        switch error {
            
        case .InvalidMusixmatchToken:
            
            PopUpHelper.showPopUp(
                delayed: false,
                message: "The tweak is unable to load lyrics from Musixmatch due to Unauthorized error. Please check or update your Musixmatch token.",
                buttonText: "OK"
            )
            break
            
        default:
            break
        }
        
        if source == .genius || !UserDefaults.geniusFallback {
            throw error
        }

        NSLog("[EeveeSpotify] Unable to load lyrics from \(source): \(error), trying Genius as fallback")
        source = .genius

        plainLyrics = try LyricsRepository.getLyrics(
            title: track.trackTitle(),
            artist: track.artistTitle(),
            spotifyTrackId: track.URI().spt_trackIdentifier(),
            source: source
        )
    }

    let lyrics = try Lyrics.with {
        $0.colors = originalLyrics?.colors ?? LyricsColors.with {
            $0.backgroundColor = Color(hex: track.extractedColorHex()).normalized.uInt32
            $0.lineColor = Color.black.uInt32
            $0.activeLineColor = Color.white.uInt32
        }
        $0.data = try LyricsHelper.composeLyricsData(plainLyrics!, source: source)
    }

    return try lyrics.serializedData()
}
