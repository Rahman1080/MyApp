# Phase 16 Report — Ask KEEPIT (Grounded Local Search)

**Date:** 2026-09-30
**Status:** ✅ Complete
**Tests:** 356/356 passing (13 new Phase 16 tests)
**Analyzer:** Clean (no issues)

## What was built

Phase 16 introduces "Ask KEEPIT" — natural language search over local data. Deterministic pattern matching, no LLM, no network. Every answer is grounded in actual database records.

### `AskKeepitService` (`lib/features/ask/domain/ask_service.dart`)

**Supported intents:**
- `"where is X"` / `"where's X"` — finds item location
- `"what is in Y"` / `"what's in Y"` — lists items in a location
- `"warranty for X"` / `"warranty on X"` — warranty status for an item
- `"when did I buy X"` — purchase date for an item
- `"how much is X worth"` — recorded value for an item
- `"show me X"` / `"find X"` / `"search for X"` — keyword search
- Fallback: any other input is treated as a keyword search

**Grounding guarantees:**
- All answers come from actual DB queries via existing repositories
- If an item isn't found, the answer explicitly says "couldn't find" — never invents data
- If an item has no location/warranty/purchase/value, the answer states that fact
- No external API calls, no LLM, works fully offline

### `WarrantyRepository.forBelonging()`

Added a method to query warranties directly linked to a belonging (Phase 14+ schema).

## Verification

| Check | Result |
|-------|--------|
| `flutter analyze --no-pub` | ✅ No issues found |
| `flutter test --no-pub` (full suite) | ✅ 356/356 passing |

### Test breakdown (13 new in `test/phase16_ask_test.dart`)
1-7. Intent parsing for all 7 query patterns
8. "where is hammer" returns location
9. "where is X" for unknown item returns honest "couldn't find"
10. "what is in garage" returns items
11. "how much is hammer worth" returns value
12. Item without value returns "no value recorded"
13. **Never fabricates data** — unknown queries get explicit not-found answers

## Design decisions

- **Deterministic, not AI:** Pattern matching ensures predictable, testable behavior. No hallucination risk.
- **Builds on existing search:** Uses `GlobalSearchService` for keyword matching, then applies intent-specific logic.
- **Honest failures:** Every "not found" path returns a clear message. The "never fabricates" test enforces this contract.
- **Local-only:** Zero network dependencies, preserving offline-first architecture.

## Known limitations

- **UI:** The domain service is complete and tested; a conversational UI screen is not yet built (can be added as a follow-up).
- **Query coverage:** Only the 7 documented patterns are supported. Complex multi-clause queries fall back to keyword search.
- **Android build:** Cannot validate in sandbox (Gradle issues). Phase 16 touches zero files under `android/`.
- **iOS build:** Requires macOS/Xcode.

## Files changed

**New:**
- `lib/features/ask/domain/ask_service.dart`
- `test/phase16_ask_test.dart`
- `PHASE16_REPORT.md`

**Modified:**
- `lib/core/database/repositories/warranty_repository.dart` (added `forBelonging()`)

## Constraints honored

- ✅ Existing features preserved (all 343 prior tests still pass)
- ✅ No user data altered (read-only queries)
- ✅ Offline-first (no network dependencies)
- ✅ One codebase (Flutter/Dart)
- ✅ No fake/mock production data
- ✅ NOT a generic chatbot — grounded search over real inventory data only
