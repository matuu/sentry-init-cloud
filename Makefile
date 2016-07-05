# github.com/umcloud/clases-devops/c06/p02/Makefile
help:
	@echo "Use:"
	@echo "make deploy      ENV=prod"
	@echo "make console-log ENV=prod"
	@echo "make verify      ENV=prod"
	@echo
	@echo "make destroy     ENV=prod"
	@echo
	@echo "make snap-create ENV=stag"
	@echo "make deploy      ENV=stag"

# Validacion y seteo de ENV movido al final para permitir
# bash auto-completion

deploy:       deploy-db       deploy-web       deploy-fe
destroy:      destroy-db      destroy-web      destroy-fe
console-log:  console-log-db  console-log-web  console-log-fe


deploy-db:
	$(eval VOL_ID:=$(shell openstack volume list -f value |awk '/$(ENV)-db-vol/ { print $$1 }'))
	@test -n "$(VOL_ID)" || { echo 'ERROR: no hay volumen: "$(ENV)-db-vol"'; exit 1;}
	make do-deploy-db  EXTRA="--block-device-mapping vdb=$(VOL_ID):::0"

deploy-web:
	make do-deploy-web EXTRA="--min-count 2"

deploy-fe:
	make do-deploy-fe  # EXTRA="..."

do-deploy-%: %.tmp.yaml
	@echo "*** $(PREFIX): $(@) ***:"
	@nova list|grep -q -w -- '$(PREFIX)-$(*)' && exit 0; \
	    set -x;sleep 2;./nova-boot.sh $(PREFIX)-$(*) $(*).tmp.yaml $(EXTRA)

destroy-%:
	@nova list|awk '/\<$(PREFIX)-$(*)\>/ { print $$2 }' | xargs -rtl1 nova delete

verify:
	@echo "*** DB ***:"
	ssh -l ubuntu $(PREFIX)-db.node.cloud.um.edu.ar 'sudo mysql -uroot sentry -e "show tables from sentry;"' && echo PASS. || echo FAIL.
	@echo "*** WEB ***:"
	curl -m2 -sL http://$(PREFIX)-web-{1,2}.node.cloud.um.edu.ar/ | grep "Welcome to Sentry" && echo PASS. || echo FAIL.
	@echo "*** FE ***:"
	curl -m2 -sL http://$(PREFIX)-fe.node.cloud.um.edu.ar | grep "Welcome to Sentry" && echo PASS. || echo FAIL.

bench:
	ab -c10 -n 1000 http://$(PREFIX)-fe.node.cloud.um.edu.ar

console-log-%:
	@echo "*** $(PREFIX): $(@) ***:"
	@nova list|awk '/\<$(PREFIX)-$(*)\>/  { print $$2 }' | xargs -rtl1 nova console-log --length 40; sleep 2

LP_USER:=$(shell sed -n 1s/.*ssh-import-id.//p  ~/.ssh/authorized_keys)

%.tmp.yaml: %.yaml
	@echo "EDITAR_USUARIO=$(USER) EDITAR_LP=$(LP_USER)"
	@sed -e "s/EDITAR_USUARIO/$(USER)/" -e "s/EDITAR_LP/$(LP_USER)/" -e "s/EDITAR_ENV/$(ENV)/" $^ > $@

snap-create: snap-create-db-vol
snap-destroy: snap-destroy-db-vol

# Ejemplo:
#   snapshot: snap-stag-db-vol  (desde prod-db-vol)
#     volume: stag-db-vol
snap-create-%:
	$(eval VOL_NAME=$(ENV)-$(*))
	# Obligado a usar cinder (en vez de openstack volume ...) debido a https://bugs.launchpad.net/python-openstackclient/+bug/1567895
	cinder snapshot-show snap-$(VOL_NAME) > /dev/null 2>&1 || cinder snapshot-create --force --name snap-$(VOL_NAME) prod-$(*)
	cinder show $(VOL_NAME) > /dev/null  2>&1 && exit 0; \
		snap_id=$$(cinder snapshot-list|awk '/snap-$(VOL_NAME)/ { print $$2 }'); test -z "$${snap_id}" || \
		cinder create --snapshot-id "$${snap_id}" --name $(VOL_NAME) 10
	openstack snapshot list
	openstack volume list

snap-destroy-%:
	$(eval VOL_NAME=$(ENV)-$(*))
	openstack volume list|grep $(VOL_NAME) || exit 0; \
		openstack volume delete $(VOL_NAME)
	openstack snapshot list|grep snap-$(VOL_NAME) || exit 0; \
		openstack snapshot delete snap-$(VOL_NAME)
	openstack snapshot list
	openstack volume list

yaml-verify: $(patsubst %.yaml, %.yaml.chk, $(wildcard *.yaml))

yaml-lint: $(patsubst %.yaml, %.yaml.lint, $(wildcard *.yaml))

%.yaml.chk: %.yaml
	python -c 'import yaml,sys;yaml.load(sys.stdin)' < $^

%.yaml.lint: %.yaml
	-yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}}}" $^


ifneq ($(MAKECMDGOALS),)
ifndef ENV
$(error Falta: export ENV={prod,stag} o make ENV={prod,stag} $(MAKECMDGOALS))
endif
endif

PREFIX:=$(ENV)-$(USER)
