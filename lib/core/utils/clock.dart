/// Injectable time source, so time-dependent rules (lockouts, timeouts,
/// request freshness) can be tested deterministically.
typedef Clock = DateTime Function();
