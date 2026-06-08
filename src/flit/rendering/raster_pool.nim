## CPU raster worker pool. Lets the main thread offload paint
## work that doesn't touch SDL or shared Pixie state.
##
## Thread safety is the caller's responsibility. Specifically:
##
## - SDL2's renderer and textures are bound to the thread that
##   created them. NEVER touch `RendererPtr`, `TexturePtr`,
##   `WindowPtr`, or `GlContextPtr` from a worker.
## - Pixie `Font` and `Image` instances mutate internal state
##   during operations like `typeset` and `fillText`. Sharing a
##   single Font across threads will race. Either clone the
##   font per worker, or run work involving a given font
##   serially through one worker.
## - Pure compute (geometry, math, hashing, copying byte buffers)
##   is fine.
##
## The intended use is sub-canvas rasterization inside a
## `RepaintBoundary`: each boundary owns its own Pixie image
## and font references, so rasterizing one boundary on a worker
## is naturally race-free.

import std/atomics

type
  RasterTaskKind = enum tkRun, tkTerminate
  RasterTaskMsg = object
    kind: RasterTaskKind
    fn: proc() {.gcsafe, nimcall.}

  RasterTask* = proc() {.gcsafe, nimcall.}

  RasterPoolImpl* = object
    queue:    Channel[RasterTaskMsg]
    pending:  Atomic[int]

  RasterPool* = ref object
    ## Fixed-size pool of worker threads. Tasks are submitted via
    ## `submit`; each is run by exactly one worker. Public fields
    ## are for introspection; treat as read-only.
    threads*:  seq[Thread[ptr RasterPoolImpl]]
    impl*:     ptr RasterPoolImpl
    isShutdown*: bool

proc workerLoop(impl: ptr RasterPoolImpl) {.thread, gcsafe, nimcall.} =
  while true:
    let msg = impl.queue.recv()
    case msg.kind
    of tkTerminate:
      break
    of tkRun:
      {.gcsafe.}:
        try: msg.fn() except CatchableError: discard
      discard impl.pending.fetchSub(1)

proc newRasterPool*(nWorkers: int = 2): RasterPool =
  ## Builds a pool of `nWorkers` worker threads. Workers block on
  ## the queue until a task arrives or `shutdown` is called.
  let impl = cast[ptr RasterPoolImpl](allocShared0(sizeof(RasterPoolImpl)))
  impl.queue.open()
  impl.pending.store(0)
  result = RasterPool(impl: impl, isShutdown: false)
  result.threads.setLen(nWorkers)
  for i in 0 ..< nWorkers:
    createThread(result.threads[i], workerLoop, impl)

proc submit*(pool: RasterPool, task: RasterTask) =
  ## Enqueues `task` for execution by the next available worker.
  ## Returns immediately. Tasks MUST be `{.nimcall, gcsafe.}` procs
  ## (not closures capturing heap state) due to Nim's cross-thread
  ## closure limitations under ORC.
  if pool.isNil or pool.impl.isNil or pool.isShutdown: return
  discard pool.impl.pending.fetchAdd(1)
  pool.impl.queue.send(RasterTaskMsg(kind: tkRun, fn: task))

proc drain*(pool: RasterPool) =
  ## Spins until every submitted task has finished.
  if pool.isNil or pool.impl.isNil: return
  while pool.impl.pending.load() > 0:
    cpuRelax()

proc shutdown*(pool: RasterPool) =
  ## Stops accepting new tasks, waits for in-flight ones to
  ## finish, signals workers to exit, then joins. Idempotent.
  if pool.isNil or pool.impl.isNil or pool.isShutdown: return
  pool.isShutdown = true
  # Wait for already-queued work to drain.
  while pool.impl.pending.load() > 0:
    cpuRelax()
  # One terminate message per worker. recv() wakes each in turn.
  for _ in 0 ..< pool.threads.len:
    pool.impl.queue.send(RasterTaskMsg(kind: tkTerminate, fn: nil))
  for i in 0 ..< pool.threads.len:
    joinThread(pool.threads[i])
  pool.threads.setLen(0)
  pool.impl.queue.close()
  deallocShared(pool.impl)
  pool.impl = nil

# Convenience: a shared global pool. Created lazily on first use.

var sharedPool: RasterPool

proc sharedRasterPool*(): RasterPool =
  ## Returns the process-wide shared pool, creating it on first
  ## access. Use this when you want background raster but don't
  ## want to manage a pool yourself.
  if sharedPool.isNil:
    sharedPool = newRasterPool(2)
  sharedPool
