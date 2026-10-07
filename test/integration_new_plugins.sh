#!/usr/bin/env bash
# Covers al_rtl, al_marimo and al_email_protect: each renders when its gate is
# on, and renders nothing when it is off.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

tmp_dir="$(mktemp -d)"
tmp_source="${tmp_dir}/source"
cleanup() {
  rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

# The public starter content is intentionally sparse. Keep plugin demo posts as
# private integration fixtures instead of requiring them in the production blog.
mkdir -p "${tmp_source}"
tar -C "${repo_root}" \
  --exclude='./.git' --exclude='./.bundle' \
  --exclude='./vendor' --exclude='./node_modules' --exclude='./_site' \
  --exclude='./.jekyll-cache' --exclude='./.jekyll-metadata' \
  -cf - . | tar -C "${tmp_source}" -xf -

mkdir -p "${tmp_source}/_posts"
cat >"${tmp_source}/_posts/2000-01-04-ci-rtl.md" <<'MARKDOWN'
---
layout: post
title: CI RTL fixture
permalink: /__ci__/plugins/rtl/
published: true
lang: fa
---

این یک نمونهٔ آزمایشی برای چیدمان راست‌به‌چپ است.
MARKDOWN

cat >"${tmp_source}/_posts/2000-01-05-ci-marimo.md" <<'MARKDOWN'
---
layout: post
title: CI marimo fixture
permalink: /__ci__/plugins/marimo/
published: true
marimo: true
---

<div class="al-marimo-inline" markdown="1">

```python
value = 1 + 1
value
```

</div>
MARKDOWN

build() {
  local name="$1"
  local override="${2:-}"
  local out="${tmp_dir}/site-${name}"
  local config="${repo_root}/_config.yml"

  if [ -n "${override}" ]; then
    config="${config},${override}"
  fi

  BUNDLE_GEMFILE="${repo_root}/Gemfile" bundle exec jekyll build \
    --source "${tmp_source}" \
    --config "${config}" \
    -d "${out}" >/dev/null
  echo "${out}"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- al_rtl -----------------------------------------------------------------

default_site="$(build default)"

rtl_page="${default_site}/__ci__/plugins/rtl/index.html"
[ -f "${rtl_page}" ] || fail "RTL fixture post was not built"

grep -q '<html[^>]*dir="rtl"' "${rtl_page}" || fail "RTL post is missing dir=\"rtl\" on <html>"
grep -q '<html[^>]*lang="fa"' "${rtl_page}" || fail "RTL post is missing lang=\"fa\" on <html>"
grep -q 'assets/al_rtl/css/rtl.css' "${rtl_page}" || fail "RTL post does not load the RTL stylesheet"

[ -f "${default_site}/assets/al_rtl/css/rtl.css" ] || fail "rtl.css is referenced but not published"

grep -q 'dir="rtl"' "${default_site}/index.html" && fail "home page wrongly marked RTL"
grep -q 'assets/al_rtl/css/rtl.css' "${default_site}/index.html" && fail "home page wrongly loads the RTL stylesheet"

# --- al_marimo --------------------------------------------------------------

marimo_page="${default_site}/__ci__/plugins/marimo/index.html"
[ -f "${marimo_page}" ] || fail "marimo fixture post was not built"

grep -q 'assets/al_marimo/js/marimo-snippets.js' "${marimo_page}" || fail "marimo post does not load the runtime"
[ -f "${default_site}/assets/al_marimo/js/marimo-snippets.js" ] || fail "marimo runtime is referenced but not published"

grep -q 'assets/al_marimo/css/marimo.css' "${marimo_page}" || fail "marimo post does not load the stylesheet"
[ -f "${default_site}/assets/al_marimo/css/marimo.css" ] || fail "marimo stylesheet is referenced but not published"

grep -q 'cdn.jsdelivr.net/npm/@marimo-team' "${marimo_page}" && fail "marimo runtime is being loaded from a CDN"
grep -q 'al_marimo' "${default_site}/index.html" && fail "home page wrongly loads marimo"

# --- al_email_protect -------------------------------------------------------

override="${tmp_dir}/protect-email.yml"
printf 'protect_email: true\n' >"${override}"
protected_site="$(build protected "${override}")"

grep -q 'assets/al_email_protect/js/email-protect.js' "${protected_site}/index.html" \
  || fail "email-protect runtime not loaded with protect_email on"
[ -f "${protected_site}/assets/al_email_protect/js/email-protect.js" ] \
  || fail "email-protect runtime referenced but not published"
grep -q 'assets/al_email_protect/css/email-protect.css' "${protected_site}/index.html" \
  || fail "email-protect stylesheet not loaded with protect_email on"
[ -f "${protected_site}/assets/al_email_protect/css/email-protect.css" ] \
  || fail "email-protect stylesheet referenced but not published"

grep -q 'al_email_protect' "${default_site}/index.html" \
  && fail "email-protect assets loaded while disabled"

echo "new plugin integration checks passed"
