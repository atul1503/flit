## RasterPool tests. Verifies tasks run, drain blocks until all
## complete, and shutdown is clean.

import std/[unittest, atomics, os]
import ../src/flit/rendering/raster_pool

# Shared state for the test tasks. Closures aren't safe to send
# across threads under ORC, so we use a global atomic counter
# that worker procs read/write.

var globalCounter: Atomic[int]
var mainThreadId: int
var nonMainCounts: Atomic[int]

proc incTask() {.gcsafe, nimcall.} =
  discard globalCounter.fetchAdd(1)

proc checkThreadTask() {.gcsafe, nimcall.} =
  if getThreadId() != mainThreadId:
    discard nonMainCounts.fetchAdd(1)

proc noopTask() {.gcsafe, nimcall.} = discard

suite "RasterPool":
  test "submit + drain runs every task to completion":
    globalCounter.store(0)
    let pool = newRasterPool(2)
    let N = 50
    for i in 0 ..< N:
      pool.submit(incTask)
    pool.drain()
    check globalCounter.load() == N
    pool.shutdown()

  test "tasks actually run on worker threads (not the submitter)":
    mainThreadId = getThreadId()
    nonMainCounts.store(0)
    let pool = newRasterPool(2)
    for i in 0 ..< 8:
      pool.submit(checkThreadTask)
    pool.drain()
    check nonMainCounts.load() == 8
    pool.shutdown()

  test "shutdown is idempotent":
    let pool = newRasterPool(1)
    pool.submit(noopTask)
    pool.drain()
    pool.shutdown()
    pool.shutdown()
    check true

  test "drain works with zero pending tasks":
    let pool = newRasterPool(1)
    pool.drain()
    pool.shutdown()
    check true
