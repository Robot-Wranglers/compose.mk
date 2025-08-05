
## BEGIN: CI/CD related targets
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
actions.docs: docs.build 
	@# Entrypoint for docs-action
actions.lint:; cmd='-color' ${docker.image.run}/rhysd/actionlint:latest 
	@# Helper for linting all action-yaml

actions.demos:
	@# Entrypoint for test-action
	${io.shell.isolated} script -q -e -c "bash --noprofile --norc -eo pipefail -x -c 'make demos'"

actions.clean cicd.clean clean.github.actions:
	@# Cleans all action-runs that are cancelled or failed
	@#
	${make} actions.list/failure actions.list/cancelled \
	| ${stream.peek} | ${jq} -r '.[].databaseId' \
	| ${make} flux.each/actions.run.delete

actions.clean.img.test:
	gh run list --workflow=img-test.yml --json databaseId,createdAt \
	| ${jq} '.[] | select(.createdAt | fromdateiso8601 < now - (60*60*10)) | .databaseId' \
	| xargs -I{} gh run delete {}

actions.clean.old:
	gh run list --limit 1000 --json databaseId,createdAt \
	| ${jq} '.[] | select(.createdAt | fromdateiso8601 < now - (60*60*24*7)) | .databaseId' \
	| xargs -I{} gh run delete {}

actions.run.delete/%:; gh run delete ${*}
	@# Helper for deleting an action

actions.list/%:; gh run list --status ${*} --json databaseId
	@# Helper for filtering action runs
