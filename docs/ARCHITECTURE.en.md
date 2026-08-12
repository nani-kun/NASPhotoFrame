# Runtime Architecture and Failure Handling

The main thread only creates UIKit objects, swaps `UIImageView` content, and handles timers. The remaining workflow is organized as follows:

```text
Timer / return to foreground
        |
        v
scanQueue (serial) -> recursive SMB2/3 enumeration -> update SQLite snapshot in one transaction
        |                                                   |
        +---------------- scan-complete notification -------+

Player -> downloadQueue (serial) -> check cache -> SMB download -> ImageIO downsampling
                                                        |
                                                        v
                                                Crossfade on main thread
```

Scanning and downloading use separate background queues. Scanning a large directory neither occupies the main thread nor prevents already cached photos from advancing. Every SMB operation uses an independent connection, avoiding stale sessions after a NAS restart, a router lease change, or a long idle period.

Index replacement follows commit-on-success semantics. A connection failure or any directory-enumeration failure leaves the old index intact, so cached photos remain playable while offline. After a new index is committed, the download queue removes cached files that are no longer referenced by the index, ensuring that photos deleted from the NAS are also removed from the iPad. Downloads are first written to `.part` files and atomically moved into place when complete, so a power loss cannot turn a partial image into a valid cache entry.

The current version intentionally does not implement system background execution. A permanent photo frame normally remains in the foreground, while standard iOS 8 applications cannot reliably run “every few hours” in the background. When the application returns to the foreground, it performs a catch-up scan according to the time of the last successful scan.
