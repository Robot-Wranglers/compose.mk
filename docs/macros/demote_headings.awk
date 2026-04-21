# Shift ATX headings down by two levels (h1 -> h3, h2 -> h4, ...) so a submodule
# doc authored with its own h1 title + h2 sections conforms to the site's staged
# convention (pages start at h3, never h1).  A shallower-than-h3 heading injected
# into an otherwise h3-based page skews the generated nav tree -- extra nesting
# levels that break the sidebar's collapse behaviour below that point.
#
# Fence-aware: a `#` on a code line inside a ``` block is a shell comment, not a
# heading, so those lines are passed through verbatim.
/^```/        { in_fence = !in_fence; print; next }
!in_fence && /^#{1,6} / { print "##" $0; next }
              { print }
