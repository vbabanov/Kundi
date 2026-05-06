# Mobile UI Verification Checklist (Post-Ingest)

## Goal
Quickly isolate whether an issue is in parser, sync, backend API, cache, or UI rendering.

## Data domains
1. Profile
   - first/last name
   - class/grade
2. Lessons
   - date ordering
   - lesson number ordering
   - subject/topic presence
3. Homework
   - description
   - photo-required flag
4. Grades
   - regular grades
   - mood/type mapping
5. Attendance
   - event code mapping
6. Derived grades (quarter/year)
   - show empty state if backend not yet providing data slice
7. Sync state
   - pending/failed counters
   - last successful sync timestamp

## State handling checks
1. loading state shown and dismissed correctly
2. empty state shown for truly empty data
3. error state shown for failed API/cache read
4. stale data is not silently presented as fresh

## Triage map
1. Parser issue:
   - connector diagnostics show parse error or missing mapping
2. Sync issue:
   - queue has failed/terminal entries
3. API issue:
   - backend read endpoint missing/incorrect data
4. Cache issue:
   - API is correct, SQLite cache not updated
5. UI issue:
   - cache data exists, render layer wrong
