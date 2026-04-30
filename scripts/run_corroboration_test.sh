#!/usr/bin/env bash
# One-shot: enqueue + reset + run analyze-quality-workout against the
# 10 most recent quality workouts, then read back what the new
# corroboration gates did.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

URL="${SUPABASE_URL}"
KEY="${SUPABASE_SERVICE_ROLE_KEY}"

H_AUTH=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json")

WORKOUT_IDS=(
  140d3e8b-0dfd-4caf-8cec-a32a349cda41
  f622b925-0663-4cab-8441-4c6ade790eeb
  cd568f17-5b37-439a-854a-f9c42049e8e4
  6ca8b912-d0e0-407b-a6ed-27edf4139c1b
  9661a5d0-5b9a-4a72-b4f4-57383401158e
  b1371b92-6dcd-4515-bb40-24a6dfffe2d3
  d9ae0886-95bb-4296-b00a-8456c48e1b15
  a6fc16ca-a514-4660-976e-762e33acc5f5
  b630a811-7529-497f-9046-2bb7bb0a2a9d
  e9930881-4e0a-4cbc-930a-a639353994db
)

# 1. Enqueue every workout (idempotent — UNIQUE(workout_id) on ai_workout_reports).
echo "─── Step 1: Enqueue all 10 quality workouts ──────────"
for wid in "${WORKOUT_IDS[@]}"; do
  resp=$(curl -sS "${H_AUTH[@]}" -X POST \
    "$URL/rest/v1/rpc/enqueue_quality_workout_for_analysis" \
    -d "{\"p_workout_id\":\"$wid\"}")
  echo "  $wid → $resp"
done

# 2. Reset existing 'complete'/'analyzing'/'failed' rows back to 'pending'
#    so the new pipeline reprocesses them under the corroboration gates.
echo
echo "─── Step 2: Reset rows to 'pending' ──────────────────"
in_clause=$(printf '"%s",' "${WORKOUT_IDS[@]}")
in_clause="(${in_clause%,})"
curl -sS "${H_AUTH[@]}" -X PATCH \
  "$URL/rest/v1/ai_workout_reports?workout_id=in.${in_clause}" \
  -H "Prefer: return=minimal" \
  -d '{
    "status": "pending",
    "report_jsonb": null,
    "summary_md": null,
    "is_suspicious": false,
    "error_message": null,
    "model_used": null,
    "analyzed_at": null
  }'
echo "  ok"

# 3. Verify everything is pending now.
echo
echo "─── Step 3: Verify pending count ─────────────────────"
curl -sS "${H_AUTH[@]}" \
  "$URL/rest/v1/ai_workout_reports?select=id,workout_id,status&workout_id=in.${in_clause}" \
  | python3 -m json.tool

# 4. Invoke the edge function. MAX_REPORTS_PER_RUN = 10, so a single call
#    handles all 10. Sequential per workout, ~1 minute total.
echo
echo "─── Step 4: Invoke analyze-quality-workout ───────────"
ids_json=$(printf '"%s",' "${WORKOUT_IDS[@]}")
ids_json="[${ids_json%,}]"

curl -sS "${H_AUTH[@]}" -X POST "$URL/functions/v1/analyze-quality-workout" \
  -d "{\"source\":\"manual_test_157\",\"workout_ids\":${ids_json}}" \
  --max-time 600 \
  | python3 -m json.tool

# 5. Read back what the corroboration gates produced.
echo
echo "─── Step 5: Read back proposals (most recent 50) ─────"
curl -sS "${H_AUTH[@]}" \
  "$URL/rest/v1/exercise_correction_proposals?select=exercise_name,field_name,operation,proposed_value,confidence,sister_corroborated,name_corroborated,multi_report_count,status,proposed_at&order=proposed_at.desc&limit=50" \
  | python3 -c "
import sys, json
for p in json.load(sys.stdin):
    flags = []
    if p['sister_corroborated']: flags.append('SISTER')
    if p['name_corroborated']: flags.append('NAME')
    if p['multi_report_count'] >= 2: flags.append(f\"MULTI({p['multi_report_count']})\")
    flag_str = '|'.join(flags) if flags else '—'
    pv = json.dumps(p['proposed_value'])[:50]
    print(f\"  {p['proposed_at'][:19]} {p['status']:<10} {p['exercise_name'][:45]:<45} {p['field_name']:<18}/{p['operation']:<6} c={p['confidence']:<4} [{flag_str}] => {pv}\")
print()
"

echo
echo "─── Step 6: Recent exercise_corrections (auto-applied) ─"
curl -sS "${H_AUTH[@]}" \
  "$URL/rest/v1/exercise_corrections?select=exercise_name,field_name,previous_value,new_value,evidence,applied_at&order=applied_at.desc&limit=20" \
  | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    pv = json.dumps(c['previous_value'])[:30]
    nv = json.dumps(c['new_value'])[:30]
    ev = c['evidence'][:60]
    print(f\"  {c['applied_at'][:19]} {c['exercise_name'][:42]:<42} {c['field_name']:<18} {pv} -> {nv}  ({ev})\")
print()
"

echo
echo "─── Step 7: Pairing signal counts ─────────────────────"
curl -sS "${H_AUTH[@]}" \
  "$URL/rest/v1/pairing_signals?select=exercise_a_name,exercise_b_name,signal_type,co_occurrence_count,avg_pairing_quality&order=co_occurrence_count.desc&limit=15" \
  | python3 -c "
import sys, json
for s in json.load(sys.stdin):
    q = f\"{s['avg_pairing_quality']:.1f}\" if s.get('avg_pairing_quality') is not None else 'n/a'
    print(f\"  [{s['signal_type']:<12}] {s['exercise_a_name'][:30]:<30} <> {s['exercise_b_name'][:30]:<30}  cooc={s['co_occurrence_count']:<3} q={q}\")
print()
"

echo
echo "─── Step 8: Per-report summary status ─────────────────"
curl -sS "${H_AUTH[@]}" \
  "$URL/rest/v1/ai_workout_reports?select=workout_id,quality_score,status,is_suspicious,is_lost_session,model_used,analyzed_at,error_message&workout_id=in.${in_clause}&order=analyzed_at.desc.nullslast" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if isinstance(data, dict):
    print(f'  ERROR: {json.dumps(data)}')
else:
    for r in data:
        sus = 'SUS' if r.get('is_suspicious') else ''
        lost = 'LOST' if r.get('is_lost_session') else ''
        err = r.get('error_message') or ''
        print(f\"  {r['workout_id'][:8]} q={r['quality_score']:<3} {r['status']:<10} {sus:<3} {lost:<4} model={(r.get('model_used') or '-')[:25]:<25} {err[:50]}\")
print()
"

echo "Done."
