## Network image widget. Fetches an image over HTTP / HTTPS in a
## background worker thread, caches the bytes by URL, and renders
## a placeholder while loading.
##
## Single worker thread per process; fetches are processed FIFO.
## Cache is per-process and grows unbounded; call
## `clearNetworkImageCache()` to release memory.
##
## Currently disabled on JS targets (the browser already has its
## own async image fetch via `<img>`; a flit web backend will get a
## DOM-image variant in a follow-up).

import std/[tables, deques, locks, os]
import ../foundation/[widget, render_object, geometry, color, key, listenable,
                       runtime, binding]
import ../widgets/basic
import ../widgets/image_widget
import ../rendering/decoration
import ../rendering/text

when not defined(js):
  import std/httpclient

type
  NetworkFetchStatus* = enum
    nfsPending, nfsLoaded, nfsError

# The cache and worker are guarded by a single lock. Operations are
# tiny (table lookup, deque push/pop) so contention is rare.

when not defined(js):
  var
    fetchLock: Lock
    fetchBytes:  Table[string, string]
    fetchStatus: Table[string, NetworkFetchStatus]
    fetchQueue:  Deque[string]
    fetchWorker: Thread[void]
    fetchWorkerStarted: bool
    completedUrls: seq[string]

  initLock(fetchLock)

  let networkImageTrigger* = newValueNotifier[int](0)
    ## Bumped each time a fetch completes. Currently kept for
    ## backwards compatibility; `NetworkImage` itself no longer
    ## subscribes here. Use per-URL notifiers (`notifierForUrl`)
    ## for finer-grained rebuilds.

  var urlNotifiers {.threadvar.}: Table[string, ValueNotifier[int]]

  proc notifierForUrl*(url: string): ValueNotifier[int] =
    ## Returns the per-URL `ValueNotifier` that's bumped when this
    ## specific URL's fetch completes. Each `NetworkImage` subscribes
    ## to its own URL's notifier so a fetch landing only rebuilds
    ## that one widget (not every NetworkImage in the tree, which
    ## was the previous behavior and caused scroll lag because each
    ## arrival invalidated every product card's RepaintBoundary).
    if not urlNotifiers.hasKey(url):
      urlNotifiers[url] = newValueNotifier[int](0)
    urlNotifiers[url]

  proc workerProc() {.thread, gcsafe.} =
    {.cast(gcsafe).}:
      var client = newHttpClient(timeout = 15000)
      while true:
        var url = ""
        withLock fetchLock:
          if fetchQueue.len > 0:
            url = fetchQueue.popFirst()
        if url.len == 0:
          sleep(40); continue
        var bytes = ""
        var status = nfsError
        try:
          bytes = client.getContent(url)
          status = nfsLoaded
        except CatchableError:
          status = nfsError
        withLock fetchLock:
          if status == nfsLoaded: fetchBytes[url] = bytes
          fetchStatus[url] = status
          completedUrls.add(url)

  proc ensureWorker() =
    if fetchWorkerStarted: return
    fetchWorkerStarted = true
    createThread(fetchWorker, workerProc)

  proc requestNetworkImage*(url: string): NetworkFetchStatus =
    ## Returns the current cached status for `url`, kicking off a
    ## fetch if not already queued or completed. Safe to call from
    ## the main UI thread.
    ensureWorker()
    withLock fetchLock:
      if fetchStatus.hasKey(url):
        return fetchStatus[url]
      fetchStatus[url] = nfsPending
      fetchQueue.addLast(url)
      return nfsPending

  proc networkImageBytes*(url: string): string =
    ## Returns the cached bytes for `url`, or `""` if not yet loaded.
    withLock fetchLock:
      if fetchBytes.hasKey(url):
        return fetchBytes[url]
    ""

  proc clearNetworkImageCache*() =
    ## Drops every cached fetch result. Pending requests in flight
    ## will land in the new cache when they complete.
    withLock fetchLock:
      fetchBytes.clear()
      fetchStatus.clear()

  proc pumpNetworkImageEvents*() =
    ## Called by the runtime once per frame. Drains the list of URLs
    ## whose fetches completed since the last call and bumps each
    ## URL's own notifier so only the matching widget rebuilds.
    var todo: seq[string]
    withLock fetchLock:
      if completedUrls.len > 0:
        todo = completedUrls
        completedUrls.setLen(0)
    if todo.len == 0: return
    for u in todo:
      if urlNotifiers.hasKey(u):
        let n = urlNotifiers[u]
        n.value = n.value + 1

else:
  proc requestNetworkImage*(url: string): NetworkFetchStatus = nfsPending
  proc networkImageBytes*(url: string): string = ""
  proc clearNetworkImageCache*() = discard
  proc pumpNetworkImageEvents*() = discard
  let networkImageTrigger* = newValueNotifier[int](0)

# The widget itself. Stateful so it can subscribe to the trigger.

type
  NetworkImage* = ref object of StatefulWidget
    ## Loads `url` in a background worker and renders the image
    ## once bytes arrive. Shows `placeholder` while loading or on
    ## error; `placeholder` is built with the placeholder color so
    ## the layout slot stays the requested size.
    url*:              string
    fit*:              ImageFit
    width*, height*:   float32
    placeholderColor*: Color

  NetworkImageState* = ref object of State

method widgetTypeName*(w: NetworkImage): string = "NetworkImage"
method createElement*(w: NetworkImage): Element = newElement(ekStateful, w)
method createState*(w: NetworkImage): State = NetworkImageState()

method build*(s: NetworkImageState, ctx: BuildContext): Widget =
  let host = NetworkImage(s.element.widget)
  discard requestNetworkImage(host.url)
  listenableBuilder(notifierForUrl(host.url),
    proc(ctx: BuildContext, tick: int): Widget =
      let current = requestNetworkImage(host.url)
      case current
      of nfsLoaded:
        let bytes = networkImageBytes(host.url)
        if bytes.len > 0:
          imageMemory(bytes = bytes, fit = host.fit,
                      width = host.width, height = host.height)
        else:
          container(width = host.width, height = host.height,
            hasDecoration = true,
            decoration = boxDecoration(color = host.placeholderColor))
      of nfsError:
        container(width = host.width, height = host.height,
          hasDecoration = true,
          decoration = boxDecoration(color = host.placeholderColor),
          child = center(child = text("image error",
            style = textStyle(fontSize = 10, color = colorWhite))))
      of nfsPending:
        container(width = host.width, height = host.height,
          hasDecoration = true,
          decoration = boxDecoration(color = host.placeholderColor)))

proc networkImage*(url: string,
                   width: float32 = 0,
                   height: float32 = 0,
                   fit: ImageFit = ifCover,
                   placeholderColor: Color = rgb(228, 230, 235),
                   key: Key = nil): NetworkImage =
  ## Builds a `NetworkImage`. Fires an HTTP fetch in a background
  ## worker on first build; subsequent builds reuse the cache.
  ##
  ## Inputs:
  ## - `url`: absolute http(s) URL of the image to load.
  ## - `width`, `height`: layout extents. Both required for stable
  ##   layout while the image is still loading. If either is 0 the
  ##   widget collapses to the loaded image's natural size (which
  ##   means layout jumps once bytes arrive).
  ## - `fit`: how to scale the loaded image into the slot. Default
  ##   `ifCover` matches typical product-photo cells.
  ## - `placeholderColor`: solid color shown while loading or on
  ##   error. Default light grey.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: mounts a `StatefulWidget` that subscribes to
  ## `networkImageTrigger` so any newly-arrived bytes trigger a
  ## rebuild for this widget.
  NetworkImage(key: key, url: url, fit: fit, width: width, height: height,
               placeholderColor: placeholderColor)
