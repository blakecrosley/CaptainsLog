#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${1:-/tmp/captainslog-key-state-packaged}"
OUTPUT_DIR="${2:-/tmp/captainslog-appstore-review}"
THUMB_DIR="$OUTPUT_DIR/thumbs"
CONTACT_SHEET="$OUTPUT_DIR/contact-sheet.png"
README_PATH="$OUTPUT_DIR/README.md"
REVIEW_HTML="$OUTPUT_DIR/review.html"

fail() {
    printf '[fail] %s\n' "$1" >&2
    exit 1
}

require_file() {
    local path="$1"
    [[ -f "$path" ]] || fail "Missing screenshot: $path"
}

make_thumb() {
    local source="$1"
    local target="$2"
    local size="$3"

    require_file "$source"
    magick "$source" \
        -resize "$size" \
        -bordercolor '#101014' \
        -border 16 \
        "$target"
}

append_row() {
    local output="$1"
    shift
    magick "$@" +append "$output"
}

if ! command -v magick >/dev/null 2>&1; then
    fail "ImageMagick 'magick' is required to create the contact sheet"
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$THUMB_DIR/iphone" "$THUMB_DIR/ipad"

printf "Captain's Log App Store screenshot contact sheet\n"
printf 'Input: %s\n' "$INPUT_DIR"
printf 'Output: %s\n\n' "$OUTPUT_DIR"

iphone_files=(
    01-dashboard.png
    02-work-map.png
    03-journal.png
    04-repositories.png
    05-ai-providers.png
    06-privacy-data.png
)

ipad_files=(
    01-dashboard.png
    02-work-map.png
    03-journal.png
    04-repositories.png
    05-ai-providers.png
    06-privacy-data.png
)

index=0
for file in "${iphone_files[@]}"; do
    index=$((index + 1))
    make_thumb "$INPUT_DIR/iphone-6.9/$file" "$THUMB_DIR/iphone/$index.png" 330x717
done

index=0
for file in "${ipad_files[@]}"; do
    index=$((index + 1))
    make_thumb "$INPUT_DIR/ipad-13/$file" "$THUMB_DIR/ipad/$index.png" 309x413
done

append_row "$THUMB_DIR/iphone-row-1.png" "$THUMB_DIR/iphone/1.png" "$THUMB_DIR/iphone/2.png" "$THUMB_DIR/iphone/3.png"
append_row "$THUMB_DIR/iphone-row-2.png" "$THUMB_DIR/iphone/4.png" "$THUMB_DIR/iphone/5.png" "$THUMB_DIR/iphone/6.png"
magick "$THUMB_DIR/iphone-row-1.png" "$THUMB_DIR/iphone-row-2.png" -append "$THUMB_DIR/iphone-sheet.png"

append_row "$THUMB_DIR/ipad-row-1.png" "$THUMB_DIR/ipad/1.png" "$THUMB_DIR/ipad/2.png" "$THUMB_DIR/ipad/3.png"
append_row "$THUMB_DIR/ipad-row-2.png" "$THUMB_DIR/ipad/4.png" "$THUMB_DIR/ipad/5.png" "$THUMB_DIR/ipad/6.png"
magick "$THUMB_DIR/ipad-row-1.png" "$THUMB_DIR/ipad-row-2.png" -append "$THUMB_DIR/ipad-sheet.png"

magick "$THUMB_DIR/iphone-sheet.png" "$THUMB_DIR/ipad-sheet.png" -append "$CONTACT_SHEET"

cat > "$README_PATH" <<'README'
# Captain's Log App Store Screenshot Review

Review `contact-sheet.png` before upload. It shows the packaged screenshots in App Store upload order:

1. Dashboard
2. Work Map
3. Journal
4. Repositories
5. AI providers
6. Privacy & Data

The first two rows are the 6.9-inch iPhone set. The last two rows are the 13-inch iPad set.

Acceptance notes:

- Dashboard and Work Map should communicate the product promise without extra marketing text.
- The set should show one calm progression: overview, long-range memory, journal evidence, repository access, optional AI keys, and privacy controls.
- Text should remain legible at App Store preview size; reject any screenshot with clipped headings, clipped controls, or dense unreadable body copy.
- The fixture account should stay neutral. Do not upload screenshots that show real private repository names, live tokens, personal email addresses, or personal GitHub data.
- No previous-app breadcrumbs, debug labels, fixture warnings, simulator chrome, or sync progress bars should be visible.
- The design should feel quiet, precise, and journal-like rather than like a generic analytics dashboard.

Approval checklist:

- iPhone and iPad sets each contain exactly these six screenshots in this order.
- The first screenshot makes Captain's Log understandable in under five seconds.
- At least one screenshot clearly shows the Work Map/histogram identity surface.
- At least one screenshot makes journal entries traceable to commit evidence.
- Repository access and Privacy & Data screenshots make GitHub permissions and data handling understandable.
- AI provider screenshots make cloud AI optional and key-backed, not required for the core app.
- No screenshot depends on color alone to explain state; labels and shape carry the meaning too.
README

cat > "$REVIEW_HTML" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Captain's Log App Store Screenshot Review</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d1117;
      --panel: #151b23;
      --panel-2: #10161d;
      --line: #303846;
      --text: #eef4fb;
      --muted: #94a0ad;
      --green: #35c85a;
      --amber: #d69a22;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 16px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
    }

    main {
      max-width: 1320px;
      margin: 0 auto;
      padding: 56px 32px 80px;
    }

    header {
      display: grid;
      gap: 16px;
      margin-bottom: 40px;
    }

    h1,
    h2,
    h3,
    p {
      margin: 0;
    }

    h1 {
      max-width: 760px;
      font-size: clamp(40px, 6vw, 76px);
      line-height: .96;
      letter-spacing: 0;
    }

    h2 {
      font-size: 28px;
      line-height: 1.1;
      margin-bottom: 18px;
    }

    h3 {
      font-size: 18px;
      line-height: 1.2;
    }

    .lede {
      max-width: 760px;
      color: var(--muted);
      font-size: 20px;
    }

    .summary {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px;
      margin: 28px 0 46px;
    }

    .summary div,
    .checklist,
    .device-set,
    .contact-sheet {
      border: 1px solid var(--line);
      border-radius: 18px;
      background: var(--panel);
    }

    .summary div {
      padding: 18px 20px;
    }

    .summary strong {
      display: block;
      margin-bottom: 4px;
      font-size: 24px;
    }

    .summary span,
    .shot p,
    .checklist li {
      color: var(--muted);
    }

    .device-set {
      padding: 24px;
      margin-bottom: 28px;
    }

    .shots {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 18px;
    }

    .shot {
      display: grid;
      gap: 10px;
      min-width: 0;
    }

    .shot img {
      display: block;
      width: 100%;
      height: auto;
      border: 1px solid #242d39;
      border-radius: 12px;
      background: var(--panel-2);
    }

    .shot p {
      font-size: 14px;
    }

    .checklist {
      padding: 24px;
      margin-top: 34px;
    }

    .checklist ul {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px 24px;
      margin: 0;
      padding-left: 20px;
    }

    .checklist li::marker {
      color: var(--green);
    }

    .contact-sheet {
      padding: 24px;
      margin-top: 28px;
    }

    .contact-sheet a {
      color: var(--green);
      text-decoration: none;
    }

    .flag {
      color: var(--amber);
    }

    @media (max-width: 820px) {
      main {
        padding: 32px 18px 56px;
      }

      .summary,
      .shots,
      .checklist ul {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Screenshot approval pass</h1>
      <p class="lede">Review the packaged Captain's Log App Store screenshots before upload. The sequence should feel quiet, precise, journal-like, and understandable without marketing copy.</p>
    </header>

    <section class="summary" aria-label="Review summary">
      <div>
        <strong>12</strong>
        <span>packaged screenshots</span>
      </div>
      <div>
        <strong>2</strong>
        <span>device families: iPhone 6.9 and iPad 13</span>
      </div>
      <div>
        <strong>6</strong>
        <span>story beats per family</span>
      </div>
    </section>

    <section class="device-set" aria-labelledby="iphone-heading">
      <h2 id="iphone-heading">iPhone 6.9-inch</h2>
      <div class="shots">
        <article class="shot">
          <img src="thumbs/iphone/1.png" alt="iPhone dashboard screenshot">
          <h3>1. Dashboard</h3>
          <p>Overview, week strip, metric lens, and Work Map.</p>
        </article>
        <article class="shot">
          <img src="thumbs/iphone/2.png" alt="iPhone Work Map screenshot">
          <h3>2. Work Map</h3>
          <p>Long-range contribution-style memory surface.</p>
        </article>
        <article class="shot">
          <img src="thumbs/iphone/3.png" alt="iPhone journal screenshot">
          <h3>3. Journal</h3>
          <p>Readable daily note backed by source commits.</p>
        </article>
        <article class="shot">
          <img src="thumbs/iphone/4.png" alt="iPhone repository access screenshot">
          <h3>4. Repositories</h3>
          <p>Repository selection and GitHub access controls.</p>
        </article>
        <article class="shot">
          <img src="thumbs/iphone/5.png" alt="iPhone AI provider screenshot">
          <h3>5. AI providers</h3>
          <p>Optional cloud providers with key-backed setup.</p>
        </article>
        <article class="shot">
          <img src="thumbs/iphone/6.png" alt="iPhone Privacy and Data screenshot">
          <h3>6. Privacy &amp; Data</h3>
          <p>Local-first privacy, controls, and support links.</p>
        </article>
      </div>
    </section>

    <section class="device-set" aria-labelledby="ipad-heading">
      <h2 id="ipad-heading">iPad 13-inch</h2>
      <div class="shots">
        <article class="shot">
          <img src="thumbs/ipad/1.png" alt="iPad dashboard screenshot">
          <h3>1. Dashboard</h3>
          <p>Adaptive overview with the selected-day journal preview.</p>
        </article>
        <article class="shot">
          <img src="thumbs/ipad/2.png" alt="iPad Work Map screenshot">
          <h3>2. Work Map</h3>
          <p>Wide history view with day evidence and rhythm stats.</p>
        </article>
        <article class="shot">
          <img src="thumbs/ipad/3.png" alt="iPad journal screenshot">
          <h3>3. Journal</h3>
          <p>Focused daily narrative with commit evidence.</p>
        </article>
        <article class="shot">
          <img src="thumbs/ipad/4.png" alt="iPad repository access screenshot">
          <h3>4. Repositories</h3>
          <p>Selection controls and repository list in a wider layout.</p>
        </article>
        <article class="shot">
          <img src="thumbs/ipad/5.png" alt="iPad AI provider screenshot">
          <h3>5. AI providers</h3>
          <p>Two-column provider and key management state.</p>
        </article>
        <article class="shot">
          <img src="thumbs/ipad/6.png" alt="iPad Privacy and Data screenshot">
          <h3>6. Privacy &amp; Data</h3>
          <p>Privacy claims, controls, and support paths.</p>
        </article>
      </div>
    </section>

    <section class="checklist" aria-labelledby="approval-heading">
      <h2 id="approval-heading">Approval checklist</h2>
      <ul>
        <li>First screenshot explains Captain's Log in under five seconds.</li>
        <li>Dashboard and Work Map are the visual identity, not secondary settings views.</li>
        <li>Journal entries are traceable to concrete commit evidence.</li>
        <li>Repository and Privacy screens make GitHub permissions understandable.</li>
        <li>No real private repositories, live keys, emails, fixture warnings, debug labels, sync bars, or simulator chrome are visible.</li>
        <li>Text remains legible and nothing clips at App Store preview scale.</li>
        <li>Cloud AI feels optional and key-backed, not required for the core app.</li>
        <li class="flag">Final approval is a human gate. This page is review support, not automatic acceptance.</li>
      </ul>
    </section>

    <section class="contact-sheet" aria-labelledby="contact-sheet-heading">
      <h2 id="contact-sheet-heading">Contact sheet</h2>
      <p><a href="contact-sheet.png">Open the compact contact sheet</a> for a single-image overview of the same sequence.</p>
    </section>
  </main>
</body>
</html>
HTML

printf '[ok] Contact sheet: %s\n' "$CONTACT_SHEET"
printf '[ok] Review notes: %s\n' "$README_PATH"
printf '[ok] Review page: %s\n' "$REVIEW_HTML"
