# Failures, Diagnostics, and Rejected Calls

Which channel a problem arrives on, and what to branch on once it does.

## Overview

Three different things can go wrong, and they are deliberately kept apart so that none of them can masquerade as another: a terminal failure, a non-terminal diagnostic, and a call that was simply ignored.

## Terminal Versus Non-Terminal

``ABPlayer/lastFailure`` holds the most recent **terminal** failure and is cleared by the next attach, source change, detach, or release. ``ABPlayer/lastDiagnostic`` holds the most recent **non-terminal** one.

An ``ABPlayerFailure`` is the existing ``ABPlayerError`` classification plus an optional ``ABErrorOrigin`` — the underlying `NSError`'s `domain` and `code`, when known — for the cases where the classification alone does not say enough.

The split exists because of one case in particular: a stream that is still loading, or still playing, routinely surfaces an `.itemErrorLogEntry` and recovers on its own. Reporting that as a failure would train consumers to ignore the failure channel.

> Tip: Branch on ``ABPlayerError/isTerminal`` — projected as ``ABPlayerFailure/isTerminal`` — rather than matching cases by hand. A future release can then classify a new case without silently changing what your handler does.

Both channels broadcast through the event stream at the same site: ``ABPlayerEvent/failureReported(_:)`` alongside the legacy ``ABPlayerEvent/failed(_:)``. New code should prefer `.failureReported`, which carries the provenance.

## Rejected Calls

A playback control call — `play`, `pause`, `seek`, `skip`, or the scrubbing trio — made while the grade is not `.current` is **ignored, not thrown**. Nothing in the return type tells you, which is why a player that appears to do nothing is almost always one that was never promoted.

Two events report it, broadcast together:

- ``ABPlayerEvent/playbackRejected`` — the legacy signal, with no detail.
- ``ABPlayerEvent/callRejected(_:grade:)`` — identifies which ``ABRejectedCall`` was ignored, and at what grade.

## Topics

### Failure Types

- ``ABPlayerError``
- ``ABPlayerFailure``
- ``ABErrorOrigin``
- ``ABRejectedCall``
