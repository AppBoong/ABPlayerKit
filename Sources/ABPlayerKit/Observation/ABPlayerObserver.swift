/// A multi-observer protocol rather than a delegate slot: several
/// consumers (e.g. the app's UI plus a metrics recorder) can observe the
/// same `ABPlayer` without fighting over a single delegate property.
@MainActor
public protocol ABPlayerObserver: AnyObject {
    func player(_ player: ABPlayer, didEmit event: ABPlayerEvent)
}
