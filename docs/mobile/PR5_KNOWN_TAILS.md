# PR5 Known Tails (Non-Blocking)

1. **Targeted future-day visual proof**
- Need one additional live run on a day/account where `upcoming_lessons` is non-empty,
  to capture explicit future-only ascending rendering proof in screenshots.
- Current behavior is covered by unit tests and runtime filtering, but final visual proof is pending.

2. **ADB automation stability**
- Week/day picker automation is occasionally flaky on some devices.
- Not a product blocker; manual verification path remains valid.

3. **Parity shadow expected drift in mixed baseline**
- During staged migration, parity mismatches can appear when v1 baseline is structurally narrower.
- Tracked via mismatch reason and counters; rollout gates already account for this.

