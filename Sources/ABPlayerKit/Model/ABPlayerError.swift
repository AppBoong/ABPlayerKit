import Foundation

/// Errors ABPlayerKit surfaces. Never thrown from the playback control surface —
/// see DESIGN-ABPlayerKit.md §6: failures are asynchronous events, not synchronous
/// throw sites a consumer cannot reliably catch.
///
/// Treat this enum as non-exhaustive, the same convention documented on
/// ``ABPlayerEvent``: minor releases may add cases, so switches outside
/// ABPlayerKit should include a `default` branch to remain source-compatible.
public enum ABPlayerError: Error, Sendable, Equatable {
    /// `AVPlayerItem.error` stringified for `Equatable`/`Sendable` safety.
    case itemFailed(description: String)
    case prerollTimedOut(after: TimeInterval)
    case prerollFailed
    case invalidGradeForSource(requested: ABPlaybackGrade)
    /// Reserved for the Cache target (Phase 3).
    case cacheUnavailable(description: String)
    /// An opt-in `ABAudioSessionPolicy` (Model/ABPlayerConfiguration.swift)
    /// failed to apply or restore against `AVAudioSession`. `NSError`
    /// stringified for `Equatable`/`Sendable` safety, same as `itemFailed`.
    /// Added in a minor release — see the non-exhaustive convention noted
    /// on this type's own doc comment above.
    case audioSessionOperationFailed(description: String)
    /// A new entry was appended to `AVPlayerItem.errorLog()` (e.g. an
    /// HTTP/network hiccup the item may still recover from) — non-terminal,
    /// unlike `.itemFailed`. Lets a consumer distinguish "still loading,
    /// but something's already gone wrong underneath" from a genuine
    /// terminal failure when playback appears to hang; see `ABPlayer.lastError`.
    /// `AVPlayerItemErrorLogEvent` stringified for `Equatable`/`Sendable`
    /// safety, same as `itemFailed`.
    /// Added in a minor release — see the non-exhaustive convention noted
    /// on this type's own doc comment above.
    case itemErrorLogEntry(description: String)
}

extension ABPlayerError {
    /// Every case is a terminal failure except `.itemErrorLogEntry`, which
    /// is a non-terminal diagnostic — a stream that's still loading or
    /// still playing routinely surfaces one of these and recovers on its
    /// own. Drives the ``ABPlayer/lastFailure``/``ABPlayer/lastDiagnostic``
    /// routing split.
    public var isTerminal: Bool {
        switch self {
        case .itemErrorLogEntry:
            return false
        case .itemFailed, .prerollTimedOut, .prerollFailed, .invalidGradeForSource,
             .cacheUnavailable, .audioSessionOperationFailed:
            return true
        }
    }
}

/// A failure's originating subsystem, reduced from `NSError`'s
/// `(domain, code)` to `Sendable`/`Equatable` primitives so it can travel on
/// a public payload.
public struct ABErrorOrigin: Sendable, Equatable, Hashable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}

/// Carries a failure's classification (``ABPlayerError``) together with its
/// originating subsystem, when known. ``ABPlayerError`` stays exactly the
/// classification scheme it always was — this type adds provenance
/// alongside it rather than into it, since adding an associated value to an
/// existing case would be a breaking change (see `POLICY-api-stability.md`
/// "Adding associated values").
public struct ABPlayerFailure: Sendable, Equatable {
    public let kind: ABPlayerError
    public let origin: ABErrorOrigin?
    public var isTerminal: Bool { kind.isTerminal }

    public init(kind: ABPlayerError, origin: ABErrorOrigin? = nil) {
        self.kind = kind
        self.origin = origin
    }
}
