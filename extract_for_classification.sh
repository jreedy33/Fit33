#!/bin/bash
# Extract id,name,equipment columns for AI classification
# Creates batches of 200 exercises each

INPUT_FILE="Final Master Correct.csv"
OUTPUT_DIR="classification_batches"

mkdir -p "$OUTPUT_DIR"

# Extract just the columns needed (id, name, equipment)
cut -d',' -f1,2,5 "$INPUT_FILE" > "${OUTPUT_DIR}/all_exercises.csv"

# Count total exercises (minus header)
TOTAL=$(($(wc -l < "${OUTPUT_DIR}/all_exercises.csv") - 1))
echo "Total exercises: $TOTAL"

# Split into batches of 200 (keeping header in each file)
HEADER=$(head -1 "${OUTPUT_DIR}/all_exercises.csv")
BATCH_SIZE=200
BATCH_NUM=1

tail -n +2 "${OUTPUT_DIR}/all_exercises.csv" | while IFS= read -r line; do
    BATCH_FILE="${OUTPUT_DIR}/batch_$(printf '%02d' $BATCH_NUM).csv"
    
    # Create new file with header if it doesn't exist
    if [ ! -f "$BATCH_FILE" ]; then
        echo "$HEADER" > "$BATCH_FILE"
    fi
    
    # Check if current batch is full
    CURRENT_COUNT=$(($(wc -l < "$BATCH_FILE") - 1))
    if [ $CURRENT_COUNT -ge $BATCH_SIZE ]; then
        BATCH_NUM=$((BATCH_NUM + 1))
        BATCH_FILE="${OUTPUT_DIR}/batch_$(printf '%02d' $BATCH_NUM).csv"
        echo "$HEADER" > "$BATCH_FILE"
    fi
    
    echo "$line" >> "$BATCH_FILE"
done

# Count batches created
BATCHES=$(ls -1 "${OUTPUT_DIR}"/batch_*.csv 2>/dev/null | wc -l)
echo "Created $BATCHES batch files in ${OUTPUT_DIR}/"
echo ""
echo "To process with AI:"
echo "1. Open AI_CLASSIFICATION_PROMPT.md"
echo "2. Copy the entire prompt"  
echo "3. Paste a batch file contents at the bottom"
echo "4. Save the output CSV"
echo "5. Repeat for each batch"
