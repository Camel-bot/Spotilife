import Foundation
import UIKit

struct MusixmatchLyricsRepository: LyricsRepository {
    private let apiUrl = "https://apic.musixmatch.com"

    private func perform(
        _ path: String,
        query: [String:Any] = [:]
    ) throws -> Data {

        var stringUrl = "\(apiUrl)\(path)"

        var finalQuery = query

        finalQuery["usertoken"] = UserDefaults.musixmatchToken
        finalQuery["app_id"] = UIDevice.current.isIpad
            ? "mac-ios-ipad-v1.0"
            : "mac-ios-v2.0"

        let queryString = finalQuery.queryString.addingPercentEncoding(
            withAllowedCharacters: .urlHostAllowed
        )!

        stringUrl += "?\(queryString)"
        
        let request = URLRequest(url: URL(string: stringUrl)!)

        let semaphore = DispatchSemaphore(value: 0)
        var data: Data?
        var error: Error?

        let task = URLSession.shared.dataTask(with: request) { response, _, err in
            error = err
            data = response
            semaphore.signal()
        }

        task.resume()
        semaphore.wait()

        if let error = error {
            throw error
        }

        return data!
    }
    
    func getLyrics(_ query: LyricsSearchQuery, options: LyricsOptions) throws -> LyricsDto {
        
        let data = try perform(
            "/ws/1.1/macro.subtitles.get",
            query: [
                "track_spotify_id": query.spotifyTrackId,
                "subtitle_format": "mxm",
                "q_track": " "
            ]
        )

        // 😭😭😭

        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let body = message["body"] as? [String: Any],
            let macroCalls = body["macro_calls"] as? [String: Any]
        else {
            throw LyricsError.DecodingError
        }

        if let header = message["header"] as? [String: Any],
            header["status_code"] as? Int == 401 {
            throw LyricsError.InvalidMusixmatchToken
        }

        if let trackSubtitlesGet = macroCalls["track.subtitles.get"] as? [String: Any],
           let subtitlesMessage = trackSubtitlesGet["message"] as? [String: Any],
           let subtitlesHeader = subtitlesMessage["header"] as? [String: Any],
           let subtitlesStatusCode = subtitlesHeader["status_code"] as? Int {
            
            if subtitlesStatusCode == 404 {
                throw LyricsError.NoSuchSong
            }
            
            if let subtitlesBody = subtitlesMessage["body"] as? [String: Any],
               let subtitleList = subtitlesBody["subtitle_list"] as? [[String: Any]],
               let firstSubtitle = subtitleList.first,
               let subtitle = firstSubtitle["subtitle"] as? [String: Any] {
                
                if let restricted = subtitle["restricted"] as? Bool, restricted {
                    throw LyricsError.MusixmatchRestricted
                }
                
                if let subtitleBody = subtitle["subtitle_body"] as? String {
                    
                    guard let subtitles = try? JSONDecoder().decode(
                        [MusixmatchSubtitle].self,
                        from: subtitleBody.data(using: .utf8)!
                    ).dropLast() else {
                        throw LyricsError.DecodingError
                    }
                    
                    if !UserDefaults.lyricsOptions.musixmatchRomanizations {
                        return LyricsDto(
                            lines: subtitles.map { subtitle in
                                LyricsLineDto(
                                    content: subtitle.text.lyricsNoteIfEmpty,
                                    offsetMs: Int(subtitle.time.total * 1000)
                                )
                            },
                            timeSynced: true
                        )
                    } else {
                        do {
                            let subtitleLang = subtitle["subtitle_language"] as? String ?? ""
                            let romajiLang = "r\(subtitleLang.prefix(1))"
                            
                            let romajiData = try perform(
                                "/ws/1.1/crowd.track.translations.get",
                                query: [
                                    "track_spotify_id": query.spotifyTrackId,
                                    "selected_language": romajiLang
                                ]
                            )
                            
                            guard
                                let romajiJson = try? JSONSerialization.jsonObject(with: romajiData, options: []) as? [String: Any],
                                let romajiMessage = romajiJson["message"] as? [String: Any],
                                let romajiBody = romajiMessage["body"] as? [String: Any],
                                let translationsList = romajiBody["translations_list"] as? [[String: Any]]
                            else {
                                throw LyricsError.DecodingError
                            }
                            
                            var translationDict: [String: String] = [:]
                            
                            for translation in translationsList {
                                if let translationInfo = translation["translation"] as? [String: Any],
                                   let translationMatch = translationInfo["subtitle_matched_line"] as? String,
                                   let translationString = translationInfo["description"] as? String {
                                    if translationMatch != translationString {
                                        translationDict[translationMatch] = translationString
                                    }

                                }
                            }
                            
                            let modifiedSubtitles = subtitles.map { subtitle in
                                var modifiedText = subtitle.text
                                for (translationMatch, translationString) in translationDict {
                                    modifiedText = modifiedText.replacingOccurrences(of: translationMatch, with: translationString)
                                }
                                return MusixmatchSubtitle(
                                    text: modifiedText,
                                    time: subtitle.time
                                )
                            }
                            
                            return LyricsDto(
                                lines: modifiedSubtitles.map { subtitle in
                                    LyricsLineDto(
                                        content: subtitle.text.lyricsNoteIfEmpty,
                                        offsetMs: Int(subtitle.time.total * 1000)
                                    )
                                },
                                timeSynced: true
                            )
                        } catch {
                            return LyricsDto(
                                lines: subtitles.map { subtitle in
                                    LyricsLineDto(
                                        content: subtitle.text.lyricsNoteIfEmpty,
                                        offsetMs: Int(subtitle.time.total * 1000)
                                    )
                                },
                                timeSynced: true
                            )
                        }
                    }
                }
            }
        }

        if let trackLyricsGet = macroCalls["track.lyrics.get"] as? [String: Any],
           let lyricsMessage = trackLyricsGet["message"] as? [String: Any],
           let lyricsHeader = lyricsMessage["header"] as? [String: Any],
           let lyricsStatusCode = lyricsHeader["status_code"] as? Int {
            
            if lyricsStatusCode == 404 {
                throw LyricsError.NoSuchSong
            }
            
            if let lyricsBody = lyricsMessage["body"] as? [String: Any],
               let lyrics = lyricsBody["lyrics"] as? [String: Any],
               let plainLyrics = lyrics["lyrics_body"] as? String {
                
                if let restricted = lyrics["restricted"] as? Bool, restricted {
                    throw LyricsError.MusixmatchRestricted
                }
                
                if (!UserDefaults.lyricsOptions.musixmatchRomanizations) {
                    return LyricsDto(
                        lines: plainLyrics
                            .components(separatedBy: "\n")
                            .dropLast()
                            .map { LyricsLineDto(content: $0.lyricsNoteIfEmpty) },
                        timeSynced: false
                    )
                } else {
                    do {
                        let subtitleLang = lyrics["lyrics_language"] as? String ?? ""
                        let romajiLang = "r\(subtitleLang.prefix(1))"
                        
                        let romajiData = try perform(
                            "/ws/1.1/crowd.track.translations.get",
                            query: [
                                "track_spotify_id": query.spotifyTrackId,
                                "selected_language": romajiLang
                            ]
                        )
                        
                        guard
                            let romajiJson = try? JSONSerialization.jsonObject(with: romajiData, options: []) as? [String: Any],
                            let romajiMessage = romajiJson["message"] as? [String: Any],
                            let romajiBody = romajiMessage["body"] as? [String: Any],
                            let translationsList = romajiBody["translations_list"] as? [[String: Any]]
                        else {
                            throw LyricsError.DecodingError
                        }
                        
                        var translationDict: [String: String] = [:]
                        
                        for translation in translationsList {
                            if let translationInfo = translation["translation"] as? [String: Any],
                               let translationMatch = translationInfo["matched_line"] as? String,
                               let translationString = translationInfo["description"] as? String {
                                if translationMatch != translationString {
                                    translationDict[translationMatch] = translationString
                                }

                            }
                        }
                        
                        let modifiedLyrics = plainLyrics
                            .components(separatedBy: "\n")
                            .dropLast()
                            .map { line in
                                var modifiedLine = line
                                for (translationMatch, translationString) in translationDict {
                                    modifiedLine = modifiedLine.replacingOccurrences(of: translationMatch, with: translationString)
                                }
                                return modifiedLine
                            }
                        
                        return LyricsDto(
                            lines: modifiedLyrics.map { LyricsLineDto(content: $0.lyricsNoteIfEmpty) },
                            timeSynced: false
                        )
                    } catch {
                        return LyricsDto(
                            lines: plainLyrics
                                .components(separatedBy: "\n")
                                .dropLast()
                                .map { LyricsLineDto(content: $0.lyricsNoteIfEmpty) },
                            timeSynced: false
                        )
                    }
                }
            }
        }

        throw LyricsError.DecodingError
    }
}
