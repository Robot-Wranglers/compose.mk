#!/usr/bin/env -S ./compose.mk mk.interpret
#
# subcommands-nested.mk:
#   Nested subcommands -- a handler that is itself a
#   `cli.subcommands.enter` sub-group, so a multi-word path threads down
#   through each level (`app db migrate`).  Built on the same reusable
#   engine as demos/subcommands.mk.
#
# USAGE:
#   ./demos/subcommands-nested.mk app status
#       -> app status ok
#   ./demos/subcommands-nested.mk app db migrate
#       -> db migrate (argv=)
#   ./demos/subcommands-nested.mk app db migrate force
#       -> db migrate (argv=force)
#   ./demos/subcommands-nested.mk app db seed users
#       -> db seed users (parametric, at depth)
#   ./demos/subcommands-nested.mk app db
#       -> usage (the db sub-group)
#   ./demos/subcommands-nested.mk app
#       -> usage (status | db)
#
# NB: dispatch requires a supervisor (see shebang); not `make -f`.
#
include compose.mk

# Top group: `status` is a leaf, `db` is a nested sub-group (another
# enter).
app:; $(call cli.subcommands.enter, namespace=.app)
.app.status:; printf 'app status ok\n'
.app.db:; $(call cli.subcommands.enter, namespace=.app.db)
.app.db.migrate:;  printf 'db migrate (argv=%s)\n' "$${argv:-}"
.app.db.seed/%:;   printf 'db seed %s (argv=%s)\n' "${*}" "$${argv:-}"

__main__: app
