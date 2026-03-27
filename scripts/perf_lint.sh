#!/bin/sh
# perf_lint.sh — Build-phase lint for performance anti-patterns
# Shows warnings in Xcode's issue navigator. Never fails the build.

SRC_DIR="${SRCROOT}/Fit33"

if [ ! -d "$SRC_DIR" ]; then
    echo "warning: [PERF LINT] Source directory not found: $SRC_DIR"
    exit 0
fi

# UserDefaults.synchronize() — synchronous disk I/O
grep -rn '\.synchronize()' "$SRC_DIR" --include='*.swift' 2>/dev/null | while IFS=: read -r file line rest; do
    echo "warning: [PERF LINT] Remove UserDefaults.synchronize() — causes synchronous disk I/O ($file:$line)"
done

# performAndWait — may block main thread
grep -rn 'performAndWait' "$SRC_DIR" --include='*.swift' 2>/dev/null | while IFS=: read -r file line rest; do
    echo "warning: [PERF LINT] performAndWait blocks calling thread — verify not from @MainActor ($file:$line)"
done

# ExerciseLibraryService.shared in files with bgContext.perform
grep -rln 'bgContext\.perform' "$SRC_DIR" --include='*.swift' 2>/dev/null | while read -r file; do
    grep -n 'ExerciseLibraryService\.shared' "$file" 2>/dev/null | while IFS=: read -r line rest; do
        echo "warning: [PERF LINT] ExerciseLibraryService.shared returns viewContext objects — verify not inside bgContext.perform ($file:$line)"
    done
done

echo "[PERF LINT] Scan complete."
exit 0
