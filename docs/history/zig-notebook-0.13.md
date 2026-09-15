# Historical Record — Zig Notebook 0.13

## Target

- Zig 0.16.0
- Typed hybrid kernel

## Recorded capabilities

- fast typed values: `i32`, `i64`, `f64`, `bool`, `[]const u8`
- numeric arithmetic with type-aware coercion
- typed `:symbols`
- typed compiler snapshots
- compiler-to-fast synchronization for mutable numeric/boolean values
- string fast path up to 256 bytes

## Example persistent state

```zig
var counter: i64 = 10;
counter += 5;
counter
```

Expected result:

```text
15
```

## Compiler bridge example

```zig
fn double(n: i64) i64 {
    return n * 2;
}

counter = double(counter);
counter
```

## Recorded limitations

- no string concatenation
- no boolean comparison operators
- arrays/struct runtime values not in fast engine
- mutable strings not synchronized back
- compiler fallback had Windows compilation latency

## Significance

This is the baseline for Zig Lab. The project should not restart from a hard-coded session demo.
