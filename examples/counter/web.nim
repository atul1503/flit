## Web entry for the counter example. Compile with:
##   nim js -d:release -o:web/app.js examples/counter/web.nim

import ./main

when isMainModule:
  runApp(Counter(), "flit-canvas")
