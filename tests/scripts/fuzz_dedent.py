#!/usr/bin/env python3
"""Fuzz the nesting-aware `.awk.cmk.dedent` (+ `indent`) stages to harden them.

Generates random NESTED banana structures (`*[|` encapsulations wrapping a `cmk.class`)
with a multi-line recipe, varying: nesting depth, per-level indent unit (2/3/4-space/tab),
recipe shape (single-line / `\\`-continuation / `case..esac` / nested case / `&&` chains),
recipe indent unit, tab+space continuation lines, and docstrings whose PROSE contains
banana-like text (`X[|`, `|)`) to exercise the `'''` fence.  Each case embeds a sentinel
`echo FUZZ_OK_<n>`; the case PASSES iff the sentinel runs and there is no crash / make
"missing separator" / spurious cmk_die.  A second batch feeds deliberately MALFORMED input
(unbalanced bananas) and asserts a clean fail-fast (non-zero, no hang, dedent error).

Deterministic (fixed seed list).  Read-only w.r.t. compose.mk, so safe to run alongside the
test suite.  Usage: python3 tests/scripts/fuzz_dedent.py [N]  (N = number of well-formed cases)
"""
import os, subprocess, sys, tempfile, random

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tests/scripts/ -> repo root
UNITS = ['  ', '   ', '    ', '\t']            # indent units chosen per level
def reindent(body_lines, unit, depth):
    """re-indent a list of (relative_depth, text) by `unit`*(depth+relative)."""
    return [unit * (depth + rd) + txt for rd, txt in body_lines]

def recipe(rng, sentinel):
    """return a list of (relative_depth, text) recipe lines under a `${self}.go:` target."""
    kind = rng.choice(['single', 'cont', 'case', 'nested', 'andchain', 'tabspace'])
    if kind == 'single':
        return [(0, '${self}.go:; @echo %s' % sentinel)]
    if kind == 'cont':
        return [(0, '${self}.go:'), (1, 'true \\'), (2, '&& echo %s' % sentinel)]
    if kind == 'case':
        return [(0, '${self}.go:'), (1, 'case x in \\'), (2, 'x) echo %s;; \\' % sentinel), (1, 'esac')]
    if kind == 'nested':
        return [(0, '${self}.go:'), (1, 'case x in \\'), (2, 'x) case y in \\'),
                (3, 'y) echo %s;; \\' % sentinel), (2, 'esac;; \\'), (1, 'esac')]
    if kind == 'andchain':
        return [(0, '${self}.go:'), (1, ': \\'), (2, '&& true \\'), (2, '&& echo %s' % sentinel)]
    if kind == 'tabspace':  # legit tab+space continuation indent on a raw recipe
        return [(0, '${self}.go:'), (1, '{ echo one; } \\'), (1, '\t  ; echo %s' % sentinel)]
    return [(0, '${self}.go:; @echo %s' % sentinel)]

def docstring(rng):
    if rng.random() < 0.5:
        return []
    # NB: use BRACKET banana forms ([| / |]) here, not paren forms ((| / |)).  A `(`/`)` in
    # docstring PROSE breaks the moduledoc `$(eval define ..)` wrapper (a separate, pre-existing
    # bug -- unbalanced parens in the eval arg); it is NOT a dedent concern.  Brackets still
    # exercise the dedent's `'''` fence (the docstring must not be scanned as a nested banana).
    prose = rng.choice([
        "a note mentioning cmk.class X[| in prose",
        "closing marker |] inside the doc text",
        "plain harmless documentation line",
        "an assignment-looking y := z[| in prose",
    ])
    return [(0, "'''"), (0, prose), (0, "'''")]

def gen(rng, n):
    depth_outer = rng.randint(0, 2)                 # number of *[| wrappers
    cls_unit = rng.choice(UNITS)
    recipe_unit = rng.choice(UNITS)
    lines = []
    # outer *[| wrappers, each at its own indent unit
    wraps = [rng.choice(UNITS) for _ in range(depth_outer)]
    ind = ''
    for w in wraps:
        lines.append(ind + '*[|')
        ind += w
    # the class opener
    lines.append(ind + 'cmk.class Fuzz%d[|' % n)
    binner = ind + cls_unit
    for rd, txt in docstring(rng):
        lines.append(binner + txt)
    for rd, txt in recipe(rng, 'FUZZ_OK_%d' % n):
        # recipe body indented under the class body by recipe_unit per relative depth
        lines.append(binner + (recipe_unit * rd if rd else '') + txt)
    lines.append(ind + '|]')
    # close the *[| wrappers (reverse)
    ind2 = ''.join(wraps)
    for w in reversed(wraps):
        ind2 = ind2[:len(ind2)-len(w)]
        lines.append(ind2 + '|]')
    lines.append('Fuzz%d it%d(||)' % (n, n))
    lines.append('__main__:; @${make} it%d.go' % n)
    return '\n'.join(lines) + '\n'

# --- recipe-position multiline dot-chain shapes -------------------------------------------------
# A dot-chain `A(| .. |).A(| .. |)` where an operand's banana straddles a newline is ONE construct
# regardless of WHERE the `(|`/`|)` land; earlier every stage disagreed (dedent balance, sugar
# lowering, the `\`-join) and it failed at a different site per shape.  These shapes exercise all of
# them through a docker-free variable-only kind, so the sentinel only prints if the chain actually
# lowers, hoists, folds and runs.  (The original fuzzer only ever emitted EOL-open/BOL-close bananas,
# which is exactly why it missed this whole class.)
CHAIN_KIND = (
    "from cmk import constructor\n"
    "constructor chain[|\n"
    "  ${self}.__cmd__ := $(value ${self})\n"
    "  ${self}.__dot__  = $(eval ${self}.__cmd__ := $(${self}.__cmd__) ; $(value ${__args__}))${self}\n"
    "  ${self}.__call__ = $(${self}.__cmd__)\n"
    "|]\n"
)
def chain_shape(rng, sentinel):
    """recipe lines (2-space head, body indent varied) for a random multiline dot-chain config."""
    b1, b2 = 'true', 'echo %s' % sentinel
    bi = rng.choice(['  ', '   ', '    '])        # inner body indent (deeper than the 2-space head)
    shape = rng.choice(['s_m', 'm_s', 'm_m', 'bslash', 'sl'])
    if shape == 'sl':                              # single line (control -- goes via lambdalift)
        return ['  chain(| %s |).chain(| %s |)' % (b1, b2)]
    if shape == 's_m':                             # single-line first, multiline second
        return ['  chain(| %s |).chain(| ' % b1, '  %s%s |)' % (bi, b2)]
    if shape == 'm_s':                             # multiline first, single-line second
        return ['  chain(| ', '  %s%s |).chain(| %s |)' % (bi, b1, b2)]
    if shape == 'm_m':                             # both multiline
        return ['  chain(| ', '  %s%s |).chain(| ' % (bi, b1), '  %s%s |)' % (bi, b2)]
    return ['  chain(| %s |) \\' % b1, '    .chain(| %s |)' % b2]   # bslash: `\`-continuation

def gen_chain(rng, n):
    return CHAIN_KIND + "__main__:\n" + "\n".join(chain_shape(rng, 'FUZZ_OK_%d' % n)) + "\n"

def run(src):
    with tempfile.NamedTemporaryFile('w', suffix='.cmk', dir=ROOT, delete=False) as f:
        f.write(src); path = f.name
    try:
        r = subprocess.run(['./compose.mk', 'cmk', 'run', path], cwd=ROOT,
                           capture_output=True, text=True, timeout=90)
        return (r.stdout + r.stderr)
    finally:
        os.unlink(path)

def main():
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 120
    seeds = list(range(N))
    fails = []
    for n in seeds:
        rng = random.Random(n * 7919 + 13)
        src = gen(rng, n)
        out = run(src)
        ok = ('FUZZ_OK_%d' % n) in out
        crash = ('missing separator' in out) or ('cmk (' in out and 'dedent' in out) or ('Segmentation' in out)
        if not ok or crash:
            fails.append((n, src, out[-600:]))
    print("well-formed: %d/%d passed" % (N - len(fails), N))
    for n, src, out in fails[:6]:
        print("\n----- FAIL seed %d -----\n%s\n--- output tail ---\n%s" % (n, src, out))

    # recipe-position multiline dot-chain batch: every shape (single/multi open per operand, plus
    # `\`-continuation) must lower + run.  The sentinel prints only if the chain executes for real.
    cfails = []
    for n in seeds:
        rng = random.Random(n * 6197 + 41)
        src = gen_chain(rng, n)
        out = run(src)
        ok = ('FUZZ_OK_%d' % n) in out
        crash = any(s in out for s in ('missing separator', 'unbalanced banana', 'prerequisites cannot',
                                       'inconsistent indentation', 'postfix treatment', 'Segmentation'))
        if not ok or crash:
            cfails.append((n, src, out[-600:]))
    print("dot-chains:  %d/%d passed" % (N - len(cfails), N))
    for n, src, out in cfails[:6]:
        print("\n----- CHAIN FAIL seed %d -----\n%s\n--- output tail ---\n%s" % (n, src, out))

    # malformed batch: unbalanced bananas must fail-fast (non-zero, no hang), not silently mis-compile
    bad = [
        "*[|\n  cmk.class X[|\n    a:; @true\n  |]\n",           # missing outer |]
        "cmk.class X[|\n  a:; @true\n",                          # missing |]
        "*[|\n  |]\n|]\n",                                        # extra close
    ]
    ff = 0
    for src in bad:
        out = run(src)
        if 'unbalanced banana' in out or 'dedent' in out or 'Error' in out or '***' in out:
            ff += 1
    print("malformed: %d/%d failed-fast cleanly" % (ff, len(bad)))

if __name__ == '__main__':
    main()
