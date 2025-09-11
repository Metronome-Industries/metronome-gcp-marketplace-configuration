.PHONY: lint lint-terraform lint-markdown lint-bash fmt fmt-terraform fmt-markdown fmt-bash


lint-terraform:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate
	terraform -chdir=terraform fmt -recursive -check

lint-markdown:
	markdownlint "**/*.md"

lint-bash:
	shfmt -d -i 2 *.sh
	shellcheck *.sh

lint: lint-terraform lint-markdown lint-bash


fmt-terraform:
	terraform -chdir=terraform fmt -recursive

fmt-markdown:
	markdownlint "**/*.md" --fix

fmt-bash:
	shfmt -w -i 2 *.sh

fmt: fmt-terraform fmt-markdown fmt-bash
