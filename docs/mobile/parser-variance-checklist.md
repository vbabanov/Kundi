# Kundelik Parser Variance Checklist

## Purpose
Track payload variances expected on first live runs and tune parser incrementally.

## Likely variance zones
1. ID bootstrap HTML
   - script variable naming differences
   - embedded JSON wrappers
2. Lessons payload
   - missing `lessonNumber`
   - date/time format differences
   - null or nested homework structures
3. Grades payload
   - absent `id` for some grade rows
   - mixed `value` formats (`5`, `5/10`, letter grades)
4. Profile payload
   - missing `className` or localized class string
   - school name encoded differently

## Tuning plan per variance
1. Capture redacted diagnostic sample.
2. Add parser fixture test for new shape.
3. Update typed parsing helper (not UI code).
4. Re-run connector tests and smoke login->ingest flow.

## Do-not rules
- Do not expose raw payload in feature UI.
- Do not bypass typed connector contracts.
- Do not hardcode per-user hacks; keep parser generalized.
