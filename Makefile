# Edots — small task runner. Nothing here is required to use the rice.
.PHONY: help lint qml release docs deploy

help:
	@printf 'Edots tasks\n\n'
	@printf '  make lint          static checks (QML, shell, Python, JSON)\n'
	@printf '  make qml           QML syntax only\n'
	@printf '  make release V=1.0.0   lint, then tag v1.0.0\n'
	@printf '  make docs          print the docs entry point\n'
	@printf '  make deploy        rsync docs/ to the docs server\n'

lint:
	./tools/lint.sh

qml:
	./tools/lint.sh --qml

release:
	@test -n "$(V)" || { printf 'usage: make release V=1.0.0\n'; exit 1; }
	./tools/release.sh "$(V)"

docs:
	@printf 'Static site: docs/index.html\n'
	@printf 'Preview:     python3 -m http.server -d docs 8080\n'

deploy:
	./tools/deploy-docs.sh
