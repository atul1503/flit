## Amazon clone. Test app to see how close flit gets to a real
## e-commerce UI without modifying the framework.
##
## Screens:
## - Home: header + sub-nav + hero + product grid + recommendations
## - Product detail: image + title + price + add to cart + description
## - Cart: line items, totals, checkout button
## - Search results: filtered product list
##
## All product data is fake but believable (real product names, real
## prices). No image assets, so product thumbnails are colored
## rectangles with the product name overlaid. That gap is the most
## obvious "not production-ready" sign.
##
## Run: nim c -r examples/amazon/main.nim

import std/[strutils, strformat, sequtils, algorithm]
import ../../src/flit
import ../../src/flit/widgets/navigator as navw

# Amazon brand colors.

let amazonNavy        = rgb(19, 26, 34)        # #131A22 header background
let amazonDarkNavy    = rgb(35, 47, 62)        # #232F3E sub-nav background
let amazonOrange      = rgb(255, 153, 0)       # #FF9900 buy buttons
let amazonOrangeDark  = rgb(252, 132, 4)       # hover / accent
let amazonYellow      = rgb(254, 189, 105)     # cart icon highlight
let amazonLink        = rgb(0, 113, 133)       # #007185 hyperlink color
let amazonLinkRed     = rgb(177, 39, 4)        # price red
let pageBg            = rgb(234, 237, 237)     # #EAEDED page background
let cardBg            = colorWhite
let textMuted         = rgb(86, 92, 95)        # secondary text
let textDark          = rgb(15, 17, 17)        # main text
let starGold          = rgb(255, 168, 0)       # rating star color
let borderGrey        = rgb(221, 221, 221)     # card border

# Product catalog. Real product names, plausible prices, plausible
# ratings, plausible review counts.

type
  Product = ref object
    id*:            int
    title*:         string
    brand*:         string
    category*:      string
    price*:         float
    originalPrice*: float           # 0 means no discount shown
    rating*:        float           # 0.0 to 5.0
    reviewCount*:   int
    prime*:         bool
    bestSeller*:    bool
    swatchColor*:   Color           # placeholder thumbnail color
    imageUrl*:      string          # if set, render networkImage
    description*:   string
    bullets*:       seq[string]

let catalog = @[
  Product(id: 1, title: "Echo Dot (5th Gen, 2022 release)",
    brand: "Amazon", category: "Electronics",
    price: 49.99, originalPrice: 79.99,
    rating: 4.7, reviewCount: 187432, prime: true, bestSeller: true,
    swatchColor: rgb(35, 47, 62),
    imageUrl: "https://picsum.photos/seed/echo-dot/300/300",
    description: "Our most popular smart speaker with Alexa. The sleek, " &
      "compact design delivers crisp vocals and balanced bass for " &
      "full sound.",
    bullets: @[
      "Bigger vibrant sound. Hear vocals come through crystal clear",
      "Voice control your entertainment, news, weather, and more",
      "Built-in temperature sensor (Charcoal)",
      "Designed with sustainability in mind, made with 55% post consumer recycled materials"]),
  Product(id: 2, title: "Kindle Paperwhite (16 GB) - Now with a 6.8\" display",
    brand: "Amazon", category: "Electronics",
    price: 149.99, originalPrice: 0.0,
    rating: 4.6, reviewCount: 92011, prime: true, bestSeller: false,
    swatchColor: rgb(60, 70, 80),
    imageUrl: "https://picsum.photos/seed/kindle/300/300",
    description: "Purpose-built for reading, with a flush-front design, " &
      "300 ppi glare-free display, and adjustable warm light.",
    bullets: @[
      "Adjustable warm light",
      "Up to 10 weeks of battery life",
      "Waterproof so you can read in the bath or by the pool",
      "16 GB stores thousands of titles"]),
  Product(id: 3, title: "Apple AirPods Pro (2nd Generation) Wireless Earbuds",
    brand: "Apple", category: "Electronics",
    price: 199.00, originalPrice: 249.00,
    rating: 4.8, reviewCount: 64127, prime: true, bestSeller: true,
    swatchColor: rgb(245, 245, 247),
    imageUrl: "https://picsum.photos/seed/airpods/300/300",
    description: "Up to 2x more Active Noise Cancellation. Adaptive " &
      "Transparency lets outside sounds in while reducing intense noise.",
    bullets: @[
      "Up to 2x more Active Noise Cancellation",
      "Adaptive Transparency",
      "Personalized Spatial Audio",
      "Multiple sizes of soft, tapered silicone tips"]),
  Product(id: 4, title: "Stanley Quencher H2.0 FlowState Tumbler 40 oz",
    brand: "Stanley", category: "Home & Kitchen",
    price: 45.00, originalPrice: 0.0,
    rating: 4.7, reviewCount: 81392, prime: true, bestSeller: true,
    swatchColor: rgb(180, 90, 90),
    imageUrl: "https://picsum.photos/seed/stanley/300/300",
    description: "Double-wall vacuum insulation keeps drinks cold for " &
      "2 days or iced for 2. Handle and rotating cover.",
    bullets: @[
      "DOUBLE WALL VACUUM INSULATION",
      "REUSABLE STRAW with leakproof FlowState Lid",
      "ADVANCED LID with 3-POSITION rotation",
      "DISHWASHER SAFE construction"]),
  Product(id: 5, title: "Fire TV Stick 4K Max streaming device",
    brand: "Amazon", category: "Electronics",
    price: 39.99, originalPrice: 59.99,
    rating: 4.7, reviewCount: 226018, prime: true, bestSeller: false,
    swatchColor: rgb(28, 33, 40),
    imageUrl: "https://picsum.photos/seed/firetv/300/300",
    description: "Our most powerful Fire TV streaming stick. Wi-Fi 6E, " &
      "Dolby Vision, Dolby Atmos, HDR10+.",
    bullets: @[
      "Wi-Fi 6E support",
      "Cinematic experience with Dolby Vision",
      "Hands-free TV with Alexa",
      "Live and free TV"]),
  Product(id: 6, title: "LEGO Star Wars The Mandalorian's N-1 Starfighter",
    brand: "LEGO", category: "Toys & Games",
    price: 59.99, originalPrice: 69.99,
    rating: 4.9, reviewCount: 8429, prime: true, bestSeller: false,
    swatchColor: rgb(240, 200, 60),
    imageUrl: "https://picsum.photos/seed/lego/300/300",
    description: "Buildable Star Wars starfighter with The Mandalorian, " &
      "Grogu, and Peli Motto minifigures.",
    bullets: @[
      "412 pieces",
      "Includes 3 LEGO minifigures",
      "Ages 9+",
      "Authentic features and details"]),
  Product(id: 7, title: "KitchenAid Artisan Series 5-Qt Stand Mixer",
    brand: "KitchenAid", category: "Home & Kitchen",
    price: 379.99, originalPrice: 449.99,
    rating: 4.8, reviewCount: 39572, prime: true, bestSeller: false,
    swatchColor: rgb(220, 60, 80),
    imageUrl: "https://picsum.photos/seed/kitchenaid/300/300",
    description: "10-speed stand mixer with 59-point planetary mixing " &
      "action. Includes coated flat beater, dough hook, and wire whip.",
    bullets: @[
      "59-Point planetary mixing action",
      "10 optimized speeds",
      "Direct-drive transmission",
      "Tilt-head design"]),
  Product(id: 8, title: "Bose QuietComfort Ultra Headphones",
    brand: "Bose", category: "Electronics",
    price: 379.00, originalPrice: 429.00,
    rating: 4.5, reviewCount: 4218, prime: true, bestSeller: false,
    swatchColor: rgb(40, 40, 45),
    imageUrl: "https://picsum.photos/seed/bose/300/300",
    description: "World-class noise cancellation with breakthrough " &
      "spatial audio. Up to 24 hours of battery life.",
    bullets: @[
      "World-class noise cancellation",
      "Breakthrough spatial audio",
      "Up to 24 hours of battery life",
      "Aware Mode and Quiet Mode"]),
  Product(id: 9, title: "Atomic Habits by James Clear (Hardcover)",
    brand: "Avery", category: "Books",
    price: 14.93, originalPrice: 27.00,
    rating: 4.8, reviewCount: 174302, prime: true, bestSeller: true,
    swatchColor: rgb(245, 230, 198),
    imageUrl: "https://picsum.photos/seed/atomic/300/300",
    description: "An Easy & Proven Way to Build Good Habits & Break Bad " &
      "Ones. #1 New York Times Bestseller.",
    bullets: @[
      "Hardcover, 320 pages",
      "Penguin Random House",
      "ISBN-13: 978-0735211292",
      "Published October 16, 2018"]),
  Product(id: 10, title: "Instant Pot Duo 7-in-1 Electric Pressure Cooker, 6 Qt",
    brand: "Instant Pot", category: "Home & Kitchen",
    price: 79.95, originalPrice: 119.95,
    rating: 4.7, reviewCount: 158844, prime: true, bestSeller: false,
    swatchColor: rgb(60, 60, 65),
    imageUrl: "https://picsum.photos/seed/instantpot/300/300",
    description: "Pressure cooker, slow cooker, rice cooker, steamer, " &
      "saute pan, yogurt maker, and warmer.",
    bullets: @[
      "7 appliances in 1",
      "13 customizable Smart Programs",
      "Easy one-touch cooking",
      "Quick one-touch pressure release"]),
  Product(id: 11, title: "Anker 633 Magnetic Wireless Charger (MagGo)",
    brand: "Anker", category: "Electronics",
    price: 89.99, originalPrice: 0.0,
    rating: 4.6, reviewCount: 12087, prime: true, bestSeller: false,
    swatchColor: rgb(245, 245, 247),
    imageUrl: "https://picsum.photos/seed/anker/300/300",
    description: "2-in-1 wireless charging stand with adjustable angle, " &
      "compatible with iPhone 15/14/13/12 series.",
    bullets: @[
      "MagSafe-compatible 7.5W wireless charging",
      "Foldable design",
      "Adjustable viewing angle",
      "Built-in PD 3.0 USB-C"]),
  Product(id: 12, title: "The Comfort Crisis by Michael Easter",
    brand: "Rodale Books", category: "Books",
    price: 18.05, originalPrice: 28.00,
    rating: 4.7, reviewCount: 9712, prime: true, bestSeller: false,
    swatchColor: rgb(200, 110, 60),
    imageUrl: "https://picsum.photos/seed/comfort/300/300",
    description: "Embrace discomfort, reclaim your wild, happy, " &
      "healthy self.",
    bullets: @[
      "Hardcover, 304 pages",
      "ISBN-13: 978-0593138762",
      "Published May 11, 2021",
      "#1 Wall Street Journal Bestseller"]),
]

# Cart state.

type
  CartLine = ref object
    productId*: int
    qty*:       int

let cartStore = newValueNotifier[seq[CartLine]](@[])

proc cartCount(): int =
  for l in cartStore.value: result += l.qty

proc cartTotal(): float =
  for l in cartStore.value:
    for p in catalog:
      if p.id == l.productId:
        result += p.price * float(l.qty)

proc cartContains(pid: int): bool =
  for l in cartStore.value:
    if l.productId == pid: return true
  false

proc addToCart(pid: int) =
  var lines = cartStore.value
  for l in lines:
    if l.productId == pid:
      l.qty += 1
      cartStore.value = lines
      return
  lines.add(CartLine(productId: pid, qty: 1))
  cartStore.value = lines

proc removeFromCart(pid: int) =
  cartStore.value = cartStore.value.filterIt(it.productId != pid)

proc bumpQty(pid: int, delta: int) =
  var lines = cartStore.value
  var kept: seq[CartLine]
  for l in lines:
    if l.productId == pid:
      let newQty = l.qty + delta
      if newQty > 0: kept.add(CartLine(productId: l.productId, qty: newQty))
    else:
      kept.add(l)
  cartStore.value = kept

proc productById(pid: int): Product =
  for p in catalog:
    if p.id == pid: return p
  nil

# Search state.

let searchQuery = newValueNotifier[string]("")

proc searchResults(): seq[Product] =
  let q = searchQuery.value.toLowerAscii.strip
  if q.len == 0: return @[]
  for p in catalog:
    if q in p.title.toLowerAscii or q in p.brand.toLowerAscii or
       q in p.category.toLowerAscii:
      result.add(p)

# Star rating renderer using the built-in vector star icon.

proc starRow(rating: float, iconSize: float32 = 14.0'f32): Widget =
  var stars: seq[Widget]
  let filled = int(rating + 0.5)
  for i in 0 ..< 5:
    let c = if i < filled: starGold else: rgb(220, 220, 220)
    stars.add(padding(padding = edgeInsetsOnly(right = 1),
      child = icon("star", size = iconSize, color = c)))
  row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = stars)

proc ratingRow(p: Product): Widget =
  row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
    starRow(p.rating),
    Widget(padding(padding = edgeInsetsOnly(left = 6),
      child = text($p.reviewCount,
        style = textStyle(fontSize = 12, color = amazonLink)))),
  ])

proc priceRow(p: Product, sizeBig: bool = false): Widget =
  let sz: float32 = if sizeBig: 22.0 else: 14.0
  let cents = $int((p.price - float(int(p.price))) * 100 + 0.5)
  let dollars = $int(p.price)
  let centStr =
    if cents.len == 1: "0" & cents
    elif cents.len == 0: "00"
    else: cents
  var children = @[
    Widget(text("$",
      style = textStyle(fontSize = sz * 0.65'f32, color = textDark))),
    Widget(text(dollars,
      style = textStyle(fontSize = sz, color = textDark))),
    Widget(padding(padding = edgeInsetsOnly(left = 1),
      child = text(centStr,
        style = textStyle(fontSize = sz * 0.65'f32, color = textDark)))),
  ]
  if p.originalPrice > p.price and p.originalPrice > 0:
    children.add(padding(padding = edgeInsetsOnly(left = 10),
      child = text("List: $" & formatFloat(p.originalPrice, ffDecimal, 2),
        style = textStyle(fontSize = 12, color = textMuted))))
  row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = children)

proc primeBadge(): Widget =
  container(
    padding = edgeInsetsSymmetric(horizontal = 6, vertical = 2),
    margin = edgeInsetsOnly(right = 6),
    hasDecoration = true,
    decoration = boxDecoration(color = amazonLink, borderRadius = 2),
    child = text("prime",
      style = textStyle(fontSize = 10, color = colorWhite)))

proc bestSellerBadge(): Widget =
  container(
    padding = edgeInsetsSymmetric(horizontal = 6, vertical = 2),
    hasDecoration = true,
    decoration = boxDecoration(color = amazonOrange, borderRadius = 2),
    child = text("Best Seller",
      style = textStyle(fontSize = 10, color = colorWhite)))

# Product thumbnail. Uses networkImage when the product has an
# imageUrl set; falls back to a colored placeholder with the name
# otherwise.

proc productThumb(p: Product, size: float32 = 160): Widget =
  if p.imageUrl.len > 0:
    clipRRect(radius = 4, child = networkImage(
      url = p.imageUrl, width = size, height = size,
      fit = ifCover, placeholderColor = p.swatchColor))
  else:
    container(
      width = size, height = size,
      hasDecoration = true,
      decoration = boxDecoration(color = p.swatchColor, borderRadius = 4),
      child = center(child = padding(padding = edgeInsetsAll(8),
        child = text(p.title,
          style = textStyle(fontSize = 11, color = colorWhite)))))

# Product card for the home grid. Click to navigate to the detail
# screen. Adds the product to the recently-viewed log.

proc productCard(p: Product, w: float32 = 200, h: float32 = 320): Widget

# Forward decls so each screen can reference the others.

proc homeScreen*(): Widget
proc productScreen*(pid: int): Widget
proc cartScreen*(): Widget
proc searchScreen*(): Widget
proc categoryScreen*(category: string): Widget
proc dealsScreen*(): Widget
proc ordersScreen*(): Widget
proc accountScreen*(): Widget
proc signInScreen*(): Widget
proc wishlistScreen*(): Widget
proc helpScreen*(): Widget
proc giftCardsScreen*(): Widget
proc sellScreen*(): Widget

# Wishlist store mirrors the cart store: a ValueNotifier of
# product IDs, watched by listenableBuilder anywhere the count or
# membership matters.
let wishlistStore = newValueNotifier[seq[int]](@[])

proc inWishlist(pid: int): bool =
  for id in wishlistStore.value:
    if id == pid: return true
  false

proc toggleWishlist(pid: int) =
  var ids = wishlistStore.value
  var found = false
  var keep: seq[int]
  for id in ids:
    if id == pid: found = true
    else: keep.add(id)
  if not found: keep.add(pid)
  wishlistStore.value = keep

# Authenticated-user store. nil = signed out. After signing in
# (sign-in form) this holds the display name so the header
# updates from "Hello, sign in" to "Hello, <name>".
let signedInUser = newValueNotifier[string]("")  # empty = signed out

# Orders store: every Buy Now or Proceed to Checkout creates an
# entry so the Orders screen has something to show.
type
  OrderLine = ref object
    productId*:  int
    qty*:        int
    placedAt*:   string
let ordersStore = newValueNotifier[seq[OrderLine]](@[])

proc placeOrder(lines: seq[CartLine]) =
  var ords = ordersStore.value
  for l in lines:
    ords.add(OrderLine(productId: l.productId, qty: l.qty,
                       placedAt: "2026-06-09"))
  ordersStore.value = ords

proc productCard(p: Product, w: float32 = 200, h: float32 = 320): Widget =
  # Wrap in RepaintBoundary so a card's bitmap is rasterized once
  # and cheaply composited on subsequent paints. Without this, every
  # scroll frame re-rasterizes the card's rrect + text + image
  # through Pixie, which costs ~1ms per primitive.
  let pid = p.id
  let openProduct: TapCallback = proc() =
    currentNavigator().push(proc(): Widget = productScreen(pid), transition = trNone)
  let toggleHeart: TapCallback = proc() = toggleWishlist(pid)
  let quickAdd: TapCallback = proc() = addToCart(pid)
  repaintBoundary(child = gestureDetector(
    behavior = htOpaque,
    onTap = openProduct,
    child = container(
      width = w, height = h,
      margin = edgeInsetsAll(6),
      padding = edgeInsetsAll(10),
      hasDecoration = true,
      decoration = boxDecoration(color = cardBg, borderRadius = 4,
        border = Border(color: borderGrey, width: 1)),
      child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                     children = @[
        # Thumbnail with wishlist heart overlay at top-right.
        Widget(stack(alignment = alignTopRight, children = @[
          Widget(center(child = productThumb(p, size = w - 24))),
          listenableBuilder(wishlistStore,
            proc(ctx: BuildContext, ids: seq[int]): Widget =
              gestureDetector(behavior = htOpaque, onTap = toggleHeart,
                child = container(
                  width = 32, height = 32,
                  margin = edgeInsetsAll(4),
                  hasDecoration = true,
                  decoration = boxDecoration(color = colorWhite, borderRadius = 16,
                    border = Border(color: borderGrey, width: 1)),
                  child = center(child = icon("heart", size = 18,
                    color = (if inWishlist(pid): amazonLinkRed else: rgb(150, 150, 150))))))),
        ])),
        sizedBox(height = 8),
        if p.bestSeller: Widget(padding(padding = edgeInsetsOnly(bottom = 4),
          child = bestSellerBadge()))
        else: Widget(sizedBox(height = 0)),
        text(p.title, style = textStyle(fontSize = 13, color = textDark)),
        sizedBox(height = 4),
        ratingRow(p),
        sizedBox(height = 6),
        priceRow(p),
        sizedBox(height = 4),
        if p.prime: Widget(primeBadge()) else: Widget(sizedBox(height = 0)),
        sizedBox(height = 6),
        # Quick "Add to Cart" button without leaving the home page.
        gestureDetector(behavior = htOpaque, onTap = quickAdd,
          child = container(
            height = 28,
            hasDecoration = true,
            decoration = boxDecoration(color = amazonYellow, borderRadius = 14),
            child = center(child = text("Add to Cart",
              style = textStyle(fontSize = 12, color = textDark))))),
      ]))))

# Top header (Amazon's dark navy bar).

proc amazonHeader(showSearch: bool = true): Widget =
  container(
    height = 60,
    hasColor = true, color = amazonNavy,
    padding = edgeInsetsSymmetric(horizontal = 12, vertical = 6),
    child = row(crossAxisAlignment = caCenter, children = @[
      # Logo (tap returns home).
      Widget(gestureDetector(
        behavior = htOpaque,
        onTap = proc() = currentNavigator().popUntil(0),
        child = padding(padding = edgeInsetsSymmetric(horizontal = 10, vertical = 4),
          child = text("amazon",
            style = textStyle(fontSize = 24, color = colorWhite))))),
      # Address picker.
      padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 4),
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(text("Deliver to Atul",
            style = textStyle(fontSize = 11, color = rgb(200, 200, 200)))),
          text("Update location",
            style = textStyle(fontSize = 14, color = colorWhite)),
        ])),
      # Search bar. Expanded to fill the middle.
      expanded(child = padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 4),
        child = container(
          height = 40,
          hasDecoration = true,
          decoration = boxDecoration(color = colorWhite, borderRadius = 4),
          child = row(crossAxisAlignment = caCenter, children = @[
            container(
              width = 70, height = 40,
              hasColor = true, color = rgb(241, 243, 246),
              child = center(child = row(
                mainAxisSize = msMin, crossAxisAlignment = caCenter, children = @[
                Widget(text("All",
                  style = textStyle(fontSize = 12, color = textDark))),
                padding(padding = edgeInsetsOnly(left = 4),
                  child = icon("chevron.down", size = 10,
                    color = textDark))]))),
            expanded(child = padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 0),
              child = textField(
                placeholder = "Search Amazon",
                onSubmitted = proc(v: string) =
                  searchQuery.value = v
                  currentNavigator().push(proc(): Widget = searchScreen(), transition = trNone),
                onChanged = proc(v: string) = searchQuery.value = v,
                style = textStyle(fontSize = 14, color = textDark)))),
            gestureDetector(
              behavior = htOpaque,
              onTap = proc() =
                currentNavigator().push(proc(): Widget = searchScreen(), transition = trNone),
              child = container(
                width = 50, height = 40,
                hasDecoration = true,
                decoration = boxDecoration(color = amazonOrange),
                child = center(child = icon("search", size = 22,
                  color = colorWhite)))),
          ])))),
      # Country / language.
      padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 4),
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(text("EN",
            style = textStyle(fontSize = 14, color = colorWhite))),
          text("English",
            style = textStyle(fontSize = 10, color = rgb(200, 200, 200))),
        ])),
      # Account & lists. Tap goes to account screen if signed-in,
      # to sign-in screen otherwise.
      gestureDetector(
        behavior = htOpaque,
        onTap = proc() =
          if signedInUser.value.len == 0:
            currentNavigator().push(proc(): Widget = signInScreen(), transition = trNone)
          else:
            currentNavigator().push(proc(): Widget = accountScreen(), transition = trNone),
        child = padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 4),
          child = listenableBuilder(signedInUser,
            proc(ctx: BuildContext, name: string): Widget =
              column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                     children = @[
                Widget(text(
                  if name.len == 0: "Hello, sign in" else: "Hello, " & name,
                  style = textStyle(fontSize = 11, color = rgb(200, 200, 200)))),
                text("Account & Lists",
                  style = textStyle(fontSize = 13, color = colorWhite)),
              ]))),
      ),
      # Returns & orders.
      gestureDetector(
        behavior = htOpaque,
        onTap = proc() =
          currentNavigator().push(proc(): Widget = ordersScreen(), transition = trNone),
        child = padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 4),
          child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                         children = @[
            Widget(text("Returns",
              style = textStyle(fontSize = 11, color = rgb(200, 200, 200)))),
            text("& Orders",
              style = textStyle(fontSize = 13, color = colorWhite)),
          ]))),
      # Cart with badge.
      gestureDetector(
        behavior = htOpaque,
        onTap = proc() =
          currentNavigator().push(proc(): Widget = cartScreen(), transition = trNone),
        child = padding(padding = edgeInsetsSymmetric(horizontal = 12, vertical = 4),
          child = listenableBuilder(cartStore,
            proc(ctx: BuildContext, lines: seq[CartLine]): Widget =
              row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
                Widget(stack(alignment = alignTopRight, children = @[
                  Widget(padding(padding = edgeInsetsAll(4),
                    child = icon("cart", size = 26, color = colorWhite))),
                  container(
                    width = 22, height = 18,
                    hasDecoration = true,
                    decoration = boxDecoration(color = amazonYellow, borderRadius = 9),
                    child = center(child = text($cartCount(),
                      style = textStyle(fontSize = 12, color = textDark)))),
                ])),
                padding(padding = edgeInsetsOnly(left = 6),
                  child = text("Cart",
                    style = textStyle(fontSize = 13, color = colorWhite))),
              ])))),
    ]))

# Secondary nav bar.

proc subNavLink(label: string, onTap: proc()): Widget =
  ## A clickable label in the sub-nav bar. Used for "Today's Deals",
  ## "Customer Service", etc. Hover state would be nice but flit's
  ## gesture detector doesn't expose hover events yet.
  let cb: TapCallback = onTap
  gestureDetector(
    behavior = htOpaque,
    onTap = cb,
    child = padding(padding = edgeInsetsSymmetric(horizontal = 10, vertical = 4),
      child = text(label,
        style = textStyle(fontSize = 13, color = colorWhite))))

proc amazonSubNav(): Widget =
  container(
    height = 38,
    hasColor = true, color = amazonDarkNavy,
    padding = edgeInsetsSymmetric(horizontal = 12, vertical = 6),
    child = row(crossAxisAlignment = caCenter, children = @[
      Widget(subNavLink("All", proc() =
        currentNavigator().push(proc(): Widget = categoryScreen("All"), transition = trNone))),
      subNavLink("Today's Deals", proc() =
        currentNavigator().push(proc(): Widget = dealsScreen(), transition = trNone)),
      subNavLink("Customer Service", proc() =
        currentNavigator().push(proc(): Widget = helpScreen(), transition = trNone)),
      subNavLink("Registry", proc() =
        currentNavigator().push(proc(): Widget = wishlistScreen(), transition = trNone)),
      subNavLink("Gift Cards", proc() =
        currentNavigator().push(proc(): Widget = giftCardsScreen(), transition = trNone)),
      subNavLink("Sell", proc() =
        currentNavigator().push(proc(): Widget = sellScreen(), transition = trNone)),
    ]))

# Hero card. Amazon's home page typically shows a big banner; we
# approximate with a wide category teaser.

proc heroBanner(): Widget =
  repaintBoundary(child = container(
    height = 220,
    margin = edgeInsetsAll(12),
    padding = edgeInsetsAll(20),
    hasDecoration = true,
    decoration = boxDecoration(color = rgb(36, 110, 145), borderRadius = 4),
    child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                   children = @[
      Widget(text("Today's biggest deals",
        style = textStyle(fontSize = 30, color = colorWhite))),
      sizedBox(height = 8),
      text("Up to 60% off select Amazon Devices",
        style = textStyle(fontSize = 16, color = rgb(220, 235, 250))),
      sizedBox(height = 20),
      gestureDetector(
        behavior = htOpaque,
        onTap = proc() =
          currentNavigator().push(proc(): Widget = dealsScreen(), transition = trNone),
        child = container(
          width = 160, height = 36,
          hasDecoration = true,
          decoration = boxDecoration(color = amazonOrange, borderRadius = 18),
          child = center(child = text("Shop now",
            style = textStyle(fontSize = 14, color = textDark))))),
    ])))

# Category card (the 2x2 grid Amazon shows above the hero on
# desktop). Each card has a title, four sub-thumbnails, and a
# "See more" link.

proc categoryCard(title, category: string, items: seq[Product]): Widget =
  let nav: TapCallback = proc() =
    currentNavigator().push(proc(): Widget = categoryScreen(category), transition = trNone)
  repaintBoundary(child = container(
    width = 280, height = 380,
    margin = edgeInsetsAll(8),
    padding = edgeInsetsAll(16),
    hasDecoration = true,
    decoration = boxDecoration(color = cardBg, borderRadius = 4,
      border = Border(color: borderGrey, width: 1)),
    child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                   children = @[
      Widget(text(title,
        style = textStyle(fontSize = 18, color = textDark))),
      sizedBox(height = 12),
      row(children = @[
        Widget(productThumb(items[0], size = 110)),
        sizedBox(width = 8),
        productThumb(items[1], size = 110),
      ]),
      sizedBox(height = 8),
      row(children = @[
        Widget(productThumb(items[2], size = 110)),
        sizedBox(width = 8),
        productThumb(items[3], size = 110),
      ]),
      sizedBox(height = 12),
      gestureDetector(behavior = htOpaque, onTap = nav,
        child = text("See more",
          style = textStyle(fontSize = 13, color = amazonLink))),
    ])))

# Home page.

proc homeScreen*(): Widget =
  let electronics = catalog.filterIt(it.category == "Electronics")
  let kitchen     = catalog.filterIt(it.category == "Home & Kitchen")
  let books       = catalog.filterIt(it.category == "Books")
  let bestSellers = catalog.filterIt(it.bestSeller)
  # Pad with first products if a filter returned fewer than 4.
  proc pad(s: seq[Product]): seq[Product] =
    result = s
    var i = 0
    while result.len < 4 and i < catalog.len:
      result.add(catalog[i]); inc i
  let elec = pad(electronics)
  let kit  = pad(kitchen)
  let bk   = pad(books)
  let bs   = pad(bestSellers)

  scrollView(child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                            children = @[
    Widget(repaintBoundary(child = amazonHeader())),
    repaintBoundary(child = amazonSubNav()),
    heroBanner(),
    # 2x2 grid of category cards using the new gridView.
    padding(padding = edgeInsetsSymmetric(horizontal = 12, vertical = 4),
      child = gridView(
        crossAxisCount = 2,
        crossAxisSpacing = 12,
        mainAxisSpacing = 12,
        children = @[
          Widget(categoryCard("Electronics under $200", "Electronics", elec)),
          categoryCard("Bestselling kitchen gear", "Home & Kitchen", kit),
          categoryCard("Top reads", "Books", bk),
          categoryCard("Best Sellers", "All", bs),
        ])),
    # Recommendations strip.
    padding(padding = edgeInsetsSymmetric(horizontal = 18, vertical = 12),
      child = text("More items to consider",
        style = textStyle(fontSize = 20, color = textDark))),
    padding(padding = edgeInsetsSymmetric(horizontal = 12, vertical = 4),
      child = row(crossAxisAlignment = caStart, children =
        catalog[0 .. min(5, catalog.high)].mapIt(Widget(productCard(it))))),
    padding(padding = edgeInsetsSymmetric(horizontal = 12, vertical = 4),
      child = row(crossAxisAlignment = caStart, children =
        catalog[6 .. catalog.high].mapIt(Widget(productCard(it))))),
    # Footer (wrapped in repaintBoundary since fully static).
    sizedBox(height = 24),
    repaintBoundary(child = container(
      height = 200,
      hasColor = true, color = amazonDarkNavy,
      padding = edgeInsetsAll(20),
      child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                     children = @[
        Widget(text("Get to Know Us  |  Make Money with Us  |  Amazon Payment Products  |  Let Us Help You",
          style = textStyle(fontSize = 13, color = colorWhite))),
        sizedBox(height = 16),
        text("Conditions of Use   Privacy Notice   Your Ads Privacy Choices",
          style = textStyle(fontSize = 11, color = rgb(180, 180, 180))),
        sizedBox(height = 8),
        text("(c) 1996-2026, Amazon.com, Inc. or its affiliates",
          style = textStyle(fontSize = 11, color = rgb(180, 180, 180))),
      ]))),
  ]))

# Product detail screen.

proc productScreen*(pid: int): Widget =
  let p = productById(pid)
  if p.isNil:
    return center(child = text("Product not found",
      style = textStyle(fontSize = 18, color = textDark)))

  let qtyController = newValueNotifier[int](1)

  scrollView(child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                            children = @[
    Widget(amazonHeader()),
    amazonSubNav(),
    padding(padding = edgeInsetsAll(16),
      child = row(crossAxisAlignment = caStart, children = @[
        # Image column.
        Widget(productThumb(p, size = 400)),
        # Detail column.
        expanded(child = padding(padding = edgeInsetsOnly(left = 24),
          child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                         children = @[
            Widget(text("Visit the " & p.brand & " Store",
              style = textStyle(fontSize = 14, color = amazonLink))),
            sizedBox(height = 8),
            text(p.title,
              style = textStyle(fontSize = 22, color = textDark)),
            sizedBox(height = 6),
            ratingRow(p),
            sizedBox(height = 12),
            container(
              height = 1, hasColor = true, color = borderGrey,
              child = sizedBox(height = 1)),
            sizedBox(height = 12),
            priceRow(p, sizeBig = true),
            sizedBox(height = 6),
            if p.originalPrice > p.price and p.originalPrice > 0:
              let saved = p.originalPrice - p.price
              let pct = int(saved / p.originalPrice * 100.0)
              Widget(text("You save: $" & formatFloat(saved, ffDecimal, 2) &
                " (" & $pct & "%)",
                style = textStyle(fontSize = 13, color = amazonLinkRed)))
            else: Widget(sizedBox(height = 0)),
            sizedBox(height = 12),
            row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
              if p.prime: primeBadge() else: sizedBox(width = 0),
              text("FREE delivery tomorrow",
                style = textStyle(fontSize = 13, color = textDark)),
            ]),
            sizedBox(height = 16),
            text("About this item",
              style = textStyle(fontSize = 16, color = textDark)),
            sizedBox(height = 6),
            column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                   children = p.bullets.mapIt(Widget(
              padding(padding = edgeInsetsSymmetric(horizontal = 0, vertical = 3),
                child = text("- " & it,
                  style = textStyle(fontSize = 13, color = textDark)))))),
            sizedBox(height = 16),
            text(p.description,
              style = textStyle(fontSize = 13, color = textDark)),
          ]))),
        # Buy box.
        sizedBox(width = 16),
        container(
          width = 240,
          padding = edgeInsetsAll(14),
          hasDecoration = true,
          decoration = boxDecoration(color = cardBg, borderRadius = 4,
            border = Border(color: borderGrey, width: 1)),
          child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                         children = @[
            Widget(priceRow(p, sizeBig = true)),
            sizedBox(height = 4),
            text("FREE Returns",
              style = textStyle(fontSize = 12, color = amazonLink)),
            sizedBox(height = 12),
            text("In Stock",
              style = textStyle(fontSize = 16, color = rgb(0, 122, 51))),
            sizedBox(height = 12),
            # Quantity stepper.
            listenableBuilder(qtyController,
              proc(ctx: BuildContext, qty: int): Widget =
                row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
                  Widget(text("Qty: ",
                    style = textStyle(fontSize = 13, color = textDark))),
                  gestureDetector(behavior = htOpaque,
                    onTap = proc() =
                      if qtyController.value > 1: qtyController.value = qtyController.value - 1,
                    child = container(width = 26, height = 26,
                      hasDecoration = true,
                      decoration = boxDecoration(color = rgb(240, 240, 240), borderRadius = 4,
                        border = Border(color: borderGrey, width: 1)),
                      child = center(child = text("-",
                        style = textStyle(fontSize = 16, color = textDark))))),
                  padding(padding = edgeInsetsSymmetric(horizontal = 10, vertical = 0),
                    child = text($qty,
                      style = textStyle(fontSize = 14, color = textDark))),
                  gestureDetector(behavior = htOpaque,
                    onTap = proc() = qtyController.value = qtyController.value + 1,
                    child = container(width = 26, height = 26,
                      hasDecoration = true,
                      decoration = boxDecoration(color = rgb(240, 240, 240), borderRadius = 4,
                        border = Border(color: borderGrey, width: 1)),
                      child = center(child = text("+",
                        style = textStyle(fontSize = 16, color = textDark))))),
                ])),
            sizedBox(height = 14),
            # Add to Cart button.
            gestureDetector(behavior = htOpaque,
              onTap = proc() =
                for i in 1 .. qtyController.value: addToCart(p.id),
              child = container(
                height = 36,
                hasDecoration = true,
                decoration = boxDecoration(color = amazonYellow, borderRadius = 18),
                child = center(child = text("Add to Cart",
                  style = textStyle(fontSize = 14, color = textDark))))),
            sizedBox(height = 10),
            # Buy Now: bypass the cart, place the order, jump to orders.
            gestureDetector(behavior = htOpaque,
              onTap = proc() =
                placeOrder(@[CartLine(productId: p.id, qty: qtyController.value)])
                currentNavigator().push(proc(): Widget = ordersScreen(), transition = trNone),
              child = container(
                height = 36,
                hasDecoration = true,
                decoration = boxDecoration(color = amazonOrange, borderRadius = 18),
                child = center(child = text("Buy Now",
                  style = textStyle(fontSize = 14, color = colorWhite))))),
            sizedBox(height = 10),
            # Add to List (wishlist).
            gestureDetector(behavior = htOpaque,
              onTap = proc() = toggleWishlist(p.id),
              child = container(
                height = 32,
                hasDecoration = true,
                decoration = boxDecoration(color = colorWhite, borderRadius = 16,
                  border = Border(color: borderGrey, width: 1)),
                child = center(child = listenableBuilder(wishlistStore,
                  proc(ctx: BuildContext, ids: seq[int]): Widget =
                    text(
                      if inWishlist(p.id): "Remove from List" else: "Add to List",
                      style = textStyle(fontSize = 13, color = textDark)))))),
            sizedBox(height = 12),
            row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
              Widget(text("Ships from:",
                style = textStyle(fontSize = 12, color = textMuted))),
              padding(padding = edgeInsetsOnly(left = 6),
                child = text("Amazon.com",
                  style = textStyle(fontSize = 12, color = textDark))),
            ]),
            row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
              Widget(text("Sold by:",
                style = textStyle(fontSize = 12, color = textMuted))),
              padding(padding = edgeInsetsOnly(left = 6),
                child = text("Amazon.com",
                  style = textStyle(fontSize = 12, color = textDark))),
            ]),
          ])),
      ])),
  ]))

# Cart screen.

proc cartLineRow(line: CartLine): Widget =
  let p = productById(line.productId)
  if p.isNil: return sizedBox(height = 0)
  container(
    padding = edgeInsetsSymmetric(horizontal = 16, vertical = 14),
    hasDecoration = true,
    decoration = boxDecoration(color = cardBg,
      border = Border(color: borderGrey, width: 1)),
    child = row(crossAxisAlignment = caStart, children = @[
      Widget(productThumb(p, size = 120)),
      sizedBox(width = 16),
      expanded(child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                              children = @[
        Widget(text(p.title,
          style = textStyle(fontSize = 16, color = textDark))),
        sizedBox(height = 4),
        text("In Stock",
          style = textStyle(fontSize = 12, color = rgb(0, 122, 51))),
        sizedBox(height = 4),
        if p.prime: primeBadge() else: sizedBox(width = 0),
        sizedBox(height = 12),
        row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
          Widget(text("Qty: ",
            style = textStyle(fontSize = 13, color = textDark))),
          gestureDetector(behavior = htOpaque,
            onTap = proc() = bumpQty(p.id, -1),
            child = container(width = 26, height = 26,
              hasDecoration = true,
              decoration = boxDecoration(color = rgb(240, 240, 240), borderRadius = 4,
                border = Border(color: borderGrey, width: 1)),
              child = center(child = text("-",
                style = textStyle(fontSize = 16, color = textDark))))),
          padding(padding = edgeInsetsSymmetric(horizontal = 10, vertical = 0),
            child = text($line.qty,
              style = textStyle(fontSize = 14, color = textDark))),
          gestureDetector(behavior = htOpaque,
            onTap = proc() = bumpQty(p.id, 1),
            child = container(width = 26, height = 26,
              hasDecoration = true,
              decoration = boxDecoration(color = rgb(240, 240, 240), borderRadius = 4,
                border = Border(color: borderGrey, width: 1)),
              child = center(child = text("+",
                style = textStyle(fontSize = 16, color = textDark))))),
          sizedBox(width = 18),
          gestureDetector(behavior = htOpaque,
            onTap = proc() = removeFromCart(p.id),
            child = text("Delete",
              style = textStyle(fontSize = 13, color = amazonLink))),
        ]),
      ])),
      sizedBox(width = 16),
      padding(padding = edgeInsetsOnly(top = 6),
        child = priceRow(p)),
    ]))

proc cartScreen*(): Widget =
  scrollView(child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                            children = @[
    Widget(amazonHeader()),
    amazonSubNav(),
    padding(padding = edgeInsetsAll(16),
      child = listenableBuilder(cartStore,
        proc(ctx: BuildContext, lines: seq[CartLine]): Widget =
          if lines.len == 0:
            container(
              padding = edgeInsetsAll(40),
              hasDecoration = true,
              decoration = boxDecoration(color = cardBg, borderRadius = 4,
                border = Border(color: borderGrey, width: 1)),
              child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                             children = @[
                Widget(text("Your Amazon Cart is empty",
                  style = textStyle(fontSize = 24, color = textDark))),
                sizedBox(height = 8),
                text("Shop today's deals  |  Sign in to your account",
                  style = textStyle(fontSize = 13, color = amazonLink)),
              ]))
          else:
            row(crossAxisAlignment = caStart, children = @[
              # Cart list.
              expanded(child = container(
                padding = edgeInsetsAll(16),
                hasDecoration = true,
                decoration = boxDecoration(color = cardBg,
                  border = Border(color: borderGrey, width: 1)),
                child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                               children = @[
                  Widget(text("Shopping Cart",
                    style = textStyle(fontSize = 28, color = textDark))),
                  sizedBox(height = 4),
                  text("Price",
                    style = textStyle(fontSize = 12, color = textMuted)),
                  sizedBox(height = 12),
                ] & lines.mapIt(Widget(cartLineRow(it))) & @[
                  Widget(padding(padding = edgeInsetsSymmetric(horizontal = 0, vertical = 14),
                    child = row(mainAxisAlignment = maEnd, children = @[
                      Widget(text("Subtotal (" & $cartCount() & " items): ",
                        style = textStyle(fontSize = 18, color = textDark))),
                      text("$" & formatFloat(cartTotal(), ffDecimal, 2),
                        style = textStyle(fontSize = 18, color = textDark)),
                    ]))),
                ]))),
              sizedBox(width = 16),
              # Checkout box.
              container(width = 280,
                padding = edgeInsetsAll(16),
                hasDecoration = true,
                decoration = boxDecoration(color = cardBg, borderRadius = 4,
                  border = Border(color: borderGrey, width: 1)),
                child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                               children = @[
                  Widget(row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
                    Widget(text("$",
                      style = textStyle(fontSize = 14, color = textDark))),
                    text(formatFloat(cartTotal(), ffDecimal, 2),
                      style = textStyle(fontSize = 22, color = textDark)),
                  ])),
                  sizedBox(height = 4),
                  text("Subtotal (" & $cartCount() & " items)",
                    style = textStyle(fontSize = 13, color = textDark)),
                  sizedBox(height = 12),
                  row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
                    Widget(text("[x] ",
                      style = textStyle(fontSize = 13, color = textDark))),
                    text("This order contains a gift",
                      style = textStyle(fontSize = 13, color = textDark)),
                  ]),
                  sizedBox(height = 14),
                  gestureDetector(behavior = htOpaque,
                    onTap = proc() =
                      placeOrder(cartStore.value)
                      cartStore.value = @[]
                      currentNavigator().push(proc(): Widget = ordersScreen(), transition = trNone),
                    child = container(
                      height = 34,
                      hasDecoration = true,
                      decoration = boxDecoration(color = amazonYellow, borderRadius = 17),
                      child = center(child = text("Proceed to checkout",
                        style = textStyle(fontSize = 13, color = textDark))))),
                ])),
            ]))),
  ]))

# Search results screen.

proc searchScreen*(): Widget =
  listenableBuilder(searchQuery,
    proc(ctx: BuildContext, q: string): Widget =
      let results = searchResults()
      scrollView(child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                                children = @[
        Widget(amazonHeader()),
        amazonSubNav(),
        padding(padding = edgeInsetsAll(16),
          child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                         children = @[
            Widget(text(
              if q.len == 0: "Type in the search bar to find products"
              else: $results.len & " results for \"" & q & "\"",
              style = textStyle(fontSize = 18, color = textDark))),
            sizedBox(height = 16),
            if results.len == 0 and q.len > 0:
              Widget(text("No matches. Try a different keyword.",
                style = textStyle(fontSize = 14, color = textMuted)))
            else:
              (proc(): Widget =
                var rows: seq[Widget]
                for r in results:
                  let p = r
                  let pid = p.id
                  rows.add(container(
                    margin = edgeInsetsOnly(bottom = 12),
                    padding = edgeInsetsAll(12),
                    hasDecoration = true,
                    decoration = boxDecoration(color = cardBg, borderRadius = 4,
                      border = Border(color: borderGrey, width: 1)),
                    child = gestureDetector(behavior = htOpaque,
                      onTap = proc() = currentNavigator().push(
                        proc(): Widget = productScreen(pid), transition = trNone),
                      child = row(crossAxisAlignment = caStart, children = @[
                        Widget(productThumb(p, size = 140)),
                        sizedBox(width = 16),
                        expanded(child = column(crossAxisAlignment = caStart,
                                                mainAxisSize = msMin, children = @[
                          Widget(text(p.title,
                            style = textStyle(fontSize = 18, color = amazonLink))),
                          sizedBox(height = 4),
                          ratingRow(p),
                          sizedBox(height = 6),
                          priceRow(p, sizeBig = true),
                          sizedBox(height = 8),
                          if p.prime: primeBadge() else: sizedBox(width = 0),
                          sizedBox(height = 8),
                          text(p.description,
                            style = textStyle(fontSize = 13, color = textDark)),
                        ])),
                      ]))))
                column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = rows))(),
          ])),
      ]))
  )

# ---- New screens added in the navigation expansion. ----

# A standard page chrome wrapper used by every secondary screen:
# header + sub-nav at top, scrollable body below, dark footer.
proc pageChrome(title: string, body: Widget): Widget =
  # Outer column uses caStretch so the footer + header span the
  # full window width. The body section uses its own padding for
  # margins around the content.
  scrollView(child = column(crossAxisAlignment = caStretch, mainAxisSize = msMin,
                            children = @[
    Widget(repaintBoundary(child = amazonHeader())),
    repaintBoundary(child = amazonSubNav()),
    padding(padding = edgeInsetsAll(16),
      child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                     children = @[
        Widget(text(title,
          style = textStyle(fontSize = 28, color = textDark))),
        sizedBox(height = 16),
        body,
      ])),
    sizedBox(height = 24),
    repaintBoundary(child = container(
      height = 120, hasColor = true, color = amazonDarkNavy,
      padding = edgeInsetsAll(20),
      child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                     children = @[
        Widget(text("(c) 1996-2026, Amazon.com, Inc.",
          style = textStyle(fontSize = 11, color = rgb(180, 180, 180)))),
      ]))),
  ]))

proc categoryScreen*(category: string): Widget =
  ## Browse all products in `category` (or "All" for the full catalog).
  ## Includes a left filter rail and a sort dropdown at the top.
  let products =
    if category == "All": catalog
    else: catalog.filterIt(it.category == category)
  let sortBy = newValueNotifier[string]("Featured")
  let body = listenableBuilder(sortBy,
    proc(ctx: BuildContext, sort: string): Widget =
      var sorted = products
      case sort
      of "Price: Low to High":
        sorted.sort(proc(a, b: Product): int = cmp(a.price, b.price))
      of "Price: High to Low":
        sorted.sort(proc(a, b: Product): int = cmp(b.price, a.price))
      of "Avg. Customer Review":
        sorted.sort(proc(a, b: Product): int = cmp(b.rating, a.rating))
      else: discard  # Featured: original order
      row(crossAxisAlignment = caStart, children = @[
        # Filter sidebar.
        Widget(container(
          width = 220, padding = edgeInsetsAll(8),
          child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                         children = @[
            Widget(text("Department",
              style = textStyle(fontSize = 16, color = textDark))),
            sizedBox(height = 6),
            text("All Departments",
              style = textStyle(fontSize = 13, color = amazonLink)),
            text("Electronics",
              style = textStyle(fontSize = 13, color = amazonLink)),
            text("Home & Kitchen",
              style = textStyle(fontSize = 13, color = amazonLink)),
            text("Books",
              style = textStyle(fontSize = 13, color = amazonLink)),
            text("Toys & Games",
              style = textStyle(fontSize = 13, color = amazonLink)),
            sizedBox(height = 16),
            text("Avg. Customer Review",
              style = textStyle(fontSize = 16, color = textDark)),
            sizedBox(height = 6),
            row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
              Widget(starRow(4.0, iconSize = 12)),
              padding(padding = edgeInsetsOnly(left = 4),
                child = text("& Up",
                  style = textStyle(fontSize = 12, color = amazonLink))),
            ]),
            sizedBox(height = 16),
            text("Prime",
              style = textStyle(fontSize = 16, color = textDark)),
            sizedBox(height = 6),
            row(crossAxisAlignment = caCenter, mainAxisSize = msMin, children = @[
              Widget(icon("check", size = 14, color = amazonLink)),
              padding(padding = edgeInsetsOnly(left = 4),
                child = text("Prime Eligible",
                  style = textStyle(fontSize = 13, color = amazonLink))),
            ]),
          ]))),
        sizedBox(width = 24),
        expanded(child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                                children = @[
          # Sort bar.
          Widget(row(crossAxisAlignment = caCenter, children = @[
            Widget(text($products.len & " results",
              style = textStyle(fontSize = 13, color = textMuted))),
            expanded(child = sizedBox(width = 0)),
            text("Sort by: ",
              style = textStyle(fontSize = 13, color = textDark)),
            dropdown[string](
              items = @["Featured", "Price: Low to High",
                        "Price: High to Low", "Avg. Customer Review"],
              value = sort,
              onChange = proc(v: string) = sortBy.value = v,
              width = 200),
          ])),
          sizedBox(height = 16),
          # Product grid.
          gridView(
            crossAxisCount = 3,
            crossAxisSpacing = 12,
            mainAxisSpacing = 12,
            children = sorted.mapIt(Widget(productCard(it, w = 220, h = 360)))),
        ])),
      ]))
  pageChrome("Results in \"" & category & "\"", body)

proc dealsScreen*(): Widget =
  let deals = catalog.filterIt(it.originalPrice > it.price and it.originalPrice > 0)
  let body = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                    children = @[
    Widget(text("Save big on top deals across every category.",
      style = textStyle(fontSize = 14, color = textMuted))),
    sizedBox(height = 16),
    gridView(
      crossAxisCount = 4,
      crossAxisSpacing = 12,
      mainAxisSpacing = 12,
      children = deals.mapIt(Widget(productCard(it, w = 200, h = 340)))),
  ])
  pageChrome("Today's Deals", body)

proc ordersScreen*(): Widget =
  let body = listenableBuilder(ordersStore,
    proc(ctx: BuildContext, ords: seq[OrderLine]): Widget =
      if ords.len == 0:
        column(crossAxisAlignment = caStart, mainAxisSize = msMin,
               children = @[
          Widget(text("You haven't placed any orders yet.",
            style = textStyle(fontSize = 16, color = textDark))),
          sizedBox(height = 8),
          text("Items you buy will show up here.",
            style = textStyle(fontSize = 13, color = textMuted)),
        ])
      else:
        var rows: seq[Widget]
        for ord in ords:
          let p = productById(ord.productId)
          if p.isNil: continue
          let pid = p.id
          let goToProduct: TapCallback = proc() =
            currentNavigator().push(proc(): Widget = productScreen(pid), transition = trNone)
          rows.add(container(
            margin = edgeInsetsOnly(bottom = 12),
            padding = edgeInsetsAll(14),
            hasDecoration = true,
            decoration = boxDecoration(color = cardBg, borderRadius = 4,
              border = Border(color: borderGrey, width: 1)),
            child = row(crossAxisAlignment = caStart, children = @[
              Widget(productThumb(p, size = 100)),
              sizedBox(width = 16),
              expanded(child = column(crossAxisAlignment = caStart,
                                      mainAxisSize = msMin, children = @[
                Widget(text("Delivered " & ord.placedAt,
                  style = textStyle(fontSize = 12, color = rgb(0, 122, 51)))),
                sizedBox(height = 4),
                text(p.title,
                  style = textStyle(fontSize = 16, color = amazonLink)),
                sizedBox(height = 4),
                text("Qty: " & $ord.qty,
                  style = textStyle(fontSize = 12, color = textMuted)),
              ])),
              column(crossAxisAlignment = caEnd, mainAxisSize = msMin,
                     children = @[
                Widget(gestureDetector(behavior = htOpaque, onTap = goToProduct,
                  child = container(
                    width = 140, height = 30,
                    hasDecoration = true,
                    decoration = boxDecoration(color = amazonYellow, borderRadius = 15),
                    child = center(child = text("Buy it again",
                      style = textStyle(fontSize = 13, color = textDark)))))),
                sizedBox(height = 6),
                container(
                  width = 140, height = 30,
                  hasDecoration = true,
                  decoration = boxDecoration(color = colorWhite, borderRadius = 15,
                    border = Border(color: borderGrey, width: 1)),
                  child = center(child = text("View order",
                    style = textStyle(fontSize = 13, color = textDark)))),
              ]),
            ])))
        column(crossAxisAlignment = caStart, mainAxisSize = msMin,
               children = rows))
  pageChrome("Your Orders", body)

proc signInScreen*(): Widget =
  let emailCtrl = newTextEditingController()
  let passCtrl = newTextEditingController()
  # center() inside a scrollView column collapses vertically, so use
  # padding for horizontal centering and let the card take its
  # natural height.
  let body = padding(padding = edgeInsetsOnly(left = 300, right = 300, top = 24),
    child = container(
    width = 360,
    padding = edgeInsetsAll(20),
    hasDecoration = true,
    decoration = boxDecoration(color = cardBg, borderRadius = 4,
      border = Border(color: borderGrey, width: 1)),
    child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                   children = @[
      Widget(text("Sign in",
        style = textStyle(fontSize = 22, color = textDark))),
      sizedBox(height = 16),
      text("Email or mobile phone number",
        style = textStyle(fontSize = 13, color = textDark)),
      sizedBox(height = 4),
      container(
        height = 36,
        hasDecoration = true,
        decoration = boxDecoration(color = colorWhite, borderRadius = 4,
          border = Border(color: borderGrey, width: 1)),
        child = padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 0),
          child = textField(controller = emailCtrl,
            placeholder = "you@example.com",
            style = textStyle(fontSize = 14, color = textDark)))),
      sizedBox(height = 12),
      text("Password",
        style = textStyle(fontSize = 13, color = textDark)),
      sizedBox(height = 4),
      container(
        height = 36,
        hasDecoration = true,
        decoration = boxDecoration(color = colorWhite, borderRadius = 4,
          border = Border(color: borderGrey, width: 1)),
        child = padding(padding = edgeInsetsSymmetric(horizontal = 8, vertical = 0),
          child = textField(controller = passCtrl,
            obscureText = true,
            placeholder = "Password",
            style = textStyle(fontSize = 14, color = textDark)))),
      sizedBox(height = 16),
      gestureDetector(behavior = htOpaque,
        onTap = proc() =
          let name =
            if emailCtrl.value.len > 0:
              let dot = emailCtrl.value.find('@')
              if dot > 0: emailCtrl.value[0 ..< dot] else: "User"
            else: "Atul"
          signedInUser.value = name
          currentNavigator().pop(),
        child = container(
          height = 36,
          hasDecoration = true,
          decoration = boxDecoration(color = amazonYellow, borderRadius = 18),
          child = center(child = text("Continue",
            style = textStyle(fontSize = 14, color = textDark))))),
      sizedBox(height = 12),
      text("By continuing, you agree to Amazon's Conditions of Use.",
        style = textStyle(fontSize = 11, color = textMuted)),
    ])))
  pageChrome("", body)

proc accountScreen*(): Widget =
  let body = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                    children = @[
    Widget(text("Your Account",
      style = textStyle(fontSize = 22, color = textDark))),
    sizedBox(height = 16),
    gridView(
      crossAxisCount = 3,
      crossAxisSpacing = 12,
      mainAxisSpacing = 12,
      children = @[
        Widget(gestureDetector(behavior = htOpaque,
          onTap = proc() = currentNavigator().push(proc(): Widget = ordersScreen(), transition = trNone),
          child = container(
            padding = edgeInsetsAll(16),
            hasDecoration = true,
            decoration = boxDecoration(color = cardBg, borderRadius = 4,
              border = Border(color: borderGrey, width: 1)),
            child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                           children = @[
              Widget(text("Your Orders",
                style = textStyle(fontSize = 16, color = textDark))),
              sizedBox(height = 4),
              text("Track, return, or buy things again",
                style = textStyle(fontSize = 12, color = textMuted)),
            ])))),
        gestureDetector(behavior = htOpaque,
          onTap = proc() = currentNavigator().push(proc(): Widget = wishlistScreen(), transition = trNone),
          child = container(
            padding = edgeInsetsAll(16),
            hasDecoration = true,
            decoration = boxDecoration(color = cardBg, borderRadius = 4,
              border = Border(color: borderGrey, width: 1)),
            child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                           children = @[
              Widget(text("Your Lists",
                style = textStyle(fontSize = 16, color = textDark))),
              sizedBox(height = 4),
              text("View, modify, and share your lists",
                style = textStyle(fontSize = 12, color = textMuted)),
            ]))),
        gestureDetector(behavior = htOpaque,
          onTap = proc() = currentNavigator().push(proc(): Widget = signInScreen(), transition = trNone),
          child = container(
            padding = edgeInsetsAll(16),
            hasDecoration = true,
            decoration = boxDecoration(color = cardBg, borderRadius = 4,
              border = Border(color: borderGrey, width: 1)),
            child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                           children = @[
              Widget(text("Login & Security",
                style = textStyle(fontSize = 16, color = textDark))),
              sizedBox(height = 4),
              text("Edit name, email, password",
                style = textStyle(fontSize = 12, color = textMuted)),
            ]))),
        gestureDetector(behavior = htOpaque,
          onTap = proc() = signedInUser.value = "",
          child = container(
            padding = edgeInsetsAll(16),
            hasDecoration = true,
            decoration = boxDecoration(color = cardBg, borderRadius = 4,
              border = Border(color: borderGrey, width: 1)),
            child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                           children = @[
              Widget(text("Sign Out",
                style = textStyle(fontSize = 16, color = textDark))),
              sizedBox(height = 4),
              text("Sign out of your account",
                style = textStyle(fontSize = 12, color = textMuted)),
            ]))),
      ]),
  ])
  pageChrome("Hello, " & (if signedInUser.value.len > 0: signedInUser.value else: "Atul"),
             body)

proc wishlistScreen*(): Widget =
  let body = listenableBuilder(wishlistStore,
    proc(ctx: BuildContext, ids: seq[int]): Widget =
      if ids.len == 0:
        column(crossAxisAlignment = caStart, mainAxisSize = msMin,
               children = @[
          Widget(text("Your list is empty.",
            style = textStyle(fontSize = 16, color = textDark))),
          sizedBox(height = 8),
          text("Tap the heart icon on any product to save it here.",
            style = textStyle(fontSize = 13, color = textMuted)),
        ])
      else:
        var rows: seq[Widget]
        for id in ids:
          let p = productById(id)
          if not p.isNil:
            rows.add(productCard(p, w = 220, h = 360))
        gridView(crossAxisCount = 3, crossAxisSpacing = 12,
                 mainAxisSpacing = 12, children = rows))
  pageChrome("Your List", body)

proc helpScreen*(): Widget =
  let body = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                    children = @[
    Widget(text("How can we help?",
      style = textStyle(fontSize = 16, color = textDark))),
    sizedBox(height = 16),
    gridView(crossAxisCount = 3, crossAxisSpacing = 12, mainAxisSpacing = 12,
             children = @[
      Widget(container(padding = edgeInsetsAll(16), hasDecoration = true,
        decoration = boxDecoration(color = cardBg, borderRadius = 4,
          border = Border(color: borderGrey, width: 1)),
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(text("Your Orders",
            style = textStyle(fontSize = 15, color = textDark))),
          sizedBox(height = 4),
          text("Track packages, return items",
            style = textStyle(fontSize = 12, color = textMuted)),
        ]))),
      container(padding = edgeInsetsAll(16), hasDecoration = true,
        decoration = boxDecoration(color = cardBg, borderRadius = 4,
          border = Border(color: borderGrey, width: 1)),
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(text("Returns & Refunds",
            style = textStyle(fontSize = 15, color = textDark))),
          sizedBox(height = 4),
          text("Print labels, track returns",
            style = textStyle(fontSize = 12, color = textMuted)),
        ])),
      container(padding = edgeInsetsAll(16), hasDecoration = true,
        decoration = boxDecoration(color = cardBg, borderRadius = 4,
          border = Border(color: borderGrey, width: 1)),
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(text("Manage Prime",
            style = textStyle(fontSize = 15, color = textDark))),
          sizedBox(height = 4),
          text("View benefits, cancel membership",
            style = textStyle(fontSize = 12, color = textMuted)),
        ])),
    ]),
  ])
  pageChrome("Customer Service", body)

proc giftCardsScreen*(): Widget =
  pageChrome("Gift Cards",
    column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
      Widget(text("Send a gift in seconds. No fees, no expiration.",
        style = textStyle(fontSize = 16, color = textDark))),
      sizedBox(height = 16),
      gridView(crossAxisCount = 4, crossAxisSpacing = 12, mainAxisSpacing = 12,
               children = @[
        Widget(container(width = 220, height = 140, hasDecoration = true,
          decoration = boxDecoration(color = rgb(54, 130, 95), borderRadius = 8),
          child = center(child = text("$25",
            style = textStyle(fontSize = 36, color = colorWhite))))),
        container(width = 220, height = 140, hasDecoration = true,
          decoration = boxDecoration(color = rgb(95, 54, 130), borderRadius = 8),
          child = center(child = text("$50",
            style = textStyle(fontSize = 36, color = colorWhite)))),
        container(width = 220, height = 140, hasDecoration = true,
          decoration = boxDecoration(color = rgb(130, 95, 54), borderRadius = 8),
          child = center(child = text("$100",
            style = textStyle(fontSize = 36, color = colorWhite)))),
        container(width = 220, height = 140, hasDecoration = true,
          decoration = boxDecoration(color = rgb(130, 54, 95), borderRadius = 8),
          child = center(child = text("Custom",
            style = textStyle(fontSize = 28, color = colorWhite)))),
      ]),
    ]))

proc sellScreen*(): Widget =
  pageChrome("Become an Amazon seller",
    column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
      Widget(text("Put your products in front of millions of customers.",
        style = textStyle(fontSize = 16, color = textDark))),
      sizedBox(height = 16),
      text("- Reach customers in 100+ countries",
        style = textStyle(fontSize = 14, color = textDark)),
      text("- Use Amazon's logistics, customer service, and storage",
        style = textStyle(fontSize = 14, color = textDark)),
      text("- $49 / month + 8-15% referral fee per item sold",
        style = textStyle(fontSize = 14, color = textDark)),
      sizedBox(height = 20),
      container(
        width = 200, height = 36,
        hasDecoration = true,
        decoration = boxDecoration(color = amazonYellow, borderRadius = 18),
        child = center(child = text("Sign up",
          style = textStyle(fontSize = 14, color = textDark)))),
    ]))

# Root.

type
  AmazonApp = ref object of StatelessWidget

method widgetTypeName(w: AmazonApp): string = "AmazonApp"
method createElement(w: AmazonApp): Element = newElement(ekStateless, w)
method build(w: AmazonApp, ctx: BuildContext): Widget =
  container(
    hasColor = true, color = pageBg,
    child = navigator(proc(): Widget = homeScreen()))

when isMainModule:
  runApp(AmazonApp())
