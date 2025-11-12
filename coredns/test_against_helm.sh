#!/usr/bin/env bash
set -euo pipefail

# CLI flags
jq_filter='.'  # default jq filter: identity
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-names)
      # Remove all keys named "name" at any level when formatting
      jq_filter='del(.. | .name?)'
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# Build the Nix derivation and collect all requisites' contents into out.jsonl
nix build .

nix-store --query --requisites result | xargs -I {} sh -c 'cat "{}"' | jq -S -c | sort > out.jsonl || true

# Temporary workspace for pretty-printed objects
tmpdir=$(mktemp -d)
helm_dir="$tmpdir/helm_pretty"
built_dir="$tmpdir/built_pretty"
mkdir -p "$helm_dir" "$built_dir"

# Ensure cleanup on exit
trap 'rm -rf "$tmpdir"' EXIT

# Split and pretty-print each JSONL line into separate files (numbered)
i=0
while IFS= read -r line; do
  printf '%s\n' "$line" | jq -S "$jq_filter" > "$helm_dir/$i.json"
  i=$((i+1))
done < <(jq -c . coredns.helm.jsonl)
helm_count=$i

i=0
while IFS= read -r line; do
  printf '%s\n' "$line" | jq -S "$jq_filter" > "$built_dir/$i.json"
  i=$((i+1))
done < <(jq -c . out.jsonl)
built_count=$i

echo "Prepared $helm_count helm objects and $built_count built objects."

min_count=$(( helm_count < built_count ? helm_count : built_count ))
if [ "$helm_count" -ne "$built_count" ]; then
  echo "Warning: object counts differ (helm: $helm_count, built: $built_count). Will compare the first $min_count objects." >&2
fi

# Compare each corresponding object using colordiff with pretty printing
diff_count=0
diff_lines_count=0
for ((i=0;i<min_count;i++)); do
  helmf="$helm_dir/$i.json"
  builtf="$built_dir/$i.json"

  kind_helm=$(jq -r '.kind // "<no-kind>"' "$helmf" 2>/dev/null || echo "<parse-error>")
  kind_built=$(jq -r '.kind // "<no-kind>"' "$builtf" 2>/dev/null || echo "<parse-error>")

  echo
  echo "============= Object $((i+1))/$min_count ======================="
  echo "Kind:  $kind_helm"
  echo

  # Use colordiff to show unified diff between the two pretty JSON files
  # Capture colordiff output to a temporary file so we can count diff lines.
  if colordiff --nobanner -u --color=always "$helmf" "$builtf"; then
    printf '\033[0;32mNo differences for object %s.\033[0m\n' "$((i+1))"
  else
    echo "Differences found for object $((i+1))."
    diff_count=$((diff_count+1))
    # Count the number of lines in the diff output and add to the running total
	d=$(diff -y --suppress-common-lines "$helmf" "$builtf" || true)
	lines=$(echo "$d" | wc -l)
    echo "Diff lines for object $((i+1)): $lines"
    diff_lines_count=$((diff_lines_count + lines))
  fi
done

# Summary
echo
echo "================================================================"
if [ "$diff_count" -eq 0 ]; then
  echo "All compared objects are identical (within the compared range)."
  exit 0
else
  echo "Number of objects with differences: $diff_count"
  echo "Number of line with differences: $diff_lines_count"
  exit 2
fi
