# Local git hooks

Lightweight pre-commit checks that run on staged Swift files only. Wired into the same `scripts/classifier_lint.py` that CI runs — so local warnings match what CI will say, just earlier.

## Activation (one-time per clone)

```bash
git config core.hooksPath .githooks
```

That's it. `core.hooksPath` is repo-local so it doesn't touch your global git config.

## What it does

`pre-commit` runs [`scripts/classifier_lint.py`](../scripts/classifier_lint.py) against any staged `Fit33/**/*.swift` file and prints warnings for catch blocks that violate QUALITY_PERFORMANCE_AGENT invariant 25a (direct `AppLogger.error` in a Supabase-touching catch instead of routing through `NetworkErrorClassifier.log(...)`).

Default behavior: **warn only, never blocks the commit**. If you want it strict for a cleanup batch:

```bash
STRICT_CLASSIFIER=1 git commit -m "..."
```

## Suppressing a specific catch

If the classifier is provably unavailable at that site (e.g. bootstrap code before auth is ready), add the inline marker inside the catch block:

```swift
catch {
    // classifier_lint:allow — classifier not yet available during app launch
    AppLogger.error("bootstrap failed: \(error)", category: .general)
}
```

The lint walks each catch block top-to-bottom with brace counting, so the marker must appear anywhere inside the block body.

## Skipping the hook entirely

```bash
git commit --no-verify
```

(The repo rules allow this. CI will still run.)
