# Benchmarks

## Required metadata

Record:

- experiment ID
- date/time
- Zig version
- OS
- CPU / architecture
- build mode
- compiler flags
- workload
- run count
- warm/cold status

## Preferred raw formats

- `.csv`
- `.json`
- `.jsonl`

## Suggested fields

```text
timestamp
experiment
case
mode
iteration
compile_ns
execute_ns
total_ns
cache_status
correct
```
