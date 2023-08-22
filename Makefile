NAME := tekton-pipeline

OPERATOR_VERSION ?= latest
PIPELINE_VERSION ?= latest
DASHBOARD_VERSION ?= latest
TRIGGER_VERSION ?= latest

RELEASE_VERSION := $(shell jx release version -previous-version=from-file:charts/tekton-pipeline/Chart.yaml)

CHART_REPO := gs://jenkinsxio/charts

PAGES_REPO:= $(shell readlink -f ../tekton-helm-chart-pages)

CHART_TRIGGER_DIR := charts/tekton-trigger

fetch: fetch-pipeline fetch-trigger fetch-dashboard

###########
# Pipeline
###########

fetch-pipeline: CHART_DIR:=charts/tekton-pipeline
ifeq ($(PIPELINE_VERSION),latest)
fetch-pipeline:: MANIFEST_URL:=curl -sS https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
else
fetch-pipeline:: MANIFEST_URL:=https://storage.googleapis.com/tekton-releases/pipeline/previous/v${PIPELINE_VERSION}/release.yaml
endif

fetch-pipeline:: .import-templates-pipeline .update-app-version-dashboard

# extract values
fetch-pipeline::
	# Remove tekton-pipelines-resolvers-ns
	rm -r $(CHART_DIR)/templates/tekton-pipelines-resolvers-ns.yaml
	# Remove tekton-pipelines-ns
	rm -r $(CHART_DIR)/templates/tekton-pipelines-ns.yaml
	# Move content of containers.resources from tekton-pipelines-remote-resolvers-deploy.yaml to remoteresolver.resources
	yq -i '.remoteresolver.resources = load("$(CHART_DIR)/templates/tekton-pipelines-remote-resolvers-deploy.yaml").spec.template.spec.containers[].resources' $(CHART_DIR)/values.yaml
	yq e -i 'del(.spec.template.spec.containers[].resources)' $(CHART_DIR)/templates/tekton-pipelines-remote-resolvers-deploy.yaml
	# Move content of data: from feature-slags-cm.yaml to featureFlags: in values.yaml
	yq -i '.featureFlags = load("$(CHART_DIR)/templates/feature-flags-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/feature-flags-cm.yaml
	# Move content of data: from config-defaults-cm.yaml to configDefaults: in values.yaml
	yq -i '.configDefaults = load("$(CHART_DIR)/templates/config-defaults-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/config-defaults-cm.yaml
	# Move content of data: from git-resolver-config-cm.yaml to gitResolverConfig: in values.yaml
	yq -i '.gitResolverConfig = load("$(CHART_DIR)/templates/git-resolver-config-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/git-resolver-config-cm.yaml
	# Move content of data: from config-leader-election-cm.yaml to leaderElectionConfig: in values.yaml
	yq -i '.leaderElectionConfig = load("$(CHART_DIR)/templates/config-leader-election-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/config-leader-election-cm.yaml
	# Move content of data: from config-observability-cm.yaml to observabilityConfig: in values.yaml
	yq -i '.observabilityConfig = load("$(CHART_DIR)/templates/config-observability-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/config-observability-cm.yaml
	# Move content of data: from config-spire-cm.yaml to spireConfig: in values.yaml
	yq -i '.spireConfig = load("$(CHART_DIR)/templates/config-spire-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/config-spire-cm.yaml
	# Move content of data: from config-events-cm.yaml to eventsConfig: in values.yaml
	yq -i '.eventsConfig = load("$(CHART_DIR)/templates/config-events-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/config-events-cm.yaml
	# Move controller image to values.yaml
	export CONTROLLER_IMAGE=`yq .spec.template.spec.containers[0].image charts/tekton-pipeline/templates/tekton-pipelines-controller-deploy.yaml` && \
		yq -i '.controller.deployment.image=env(CONTROLLER_IMAGE)' $(CHART_DIR)/values.yaml
	# Remove image: from tekton-pipelines-controller-deploy
	yq -i 'del(.spec.template.spec.containers[].image)' $(CHART_DIR)/templates/tekton-pipelines-controller-deploy.yaml
	# Make node affinity configurable
	yq -i '.webhook.affinity.nodeAffinity = load("$(CHART_DIR)/templates/tekton-pipelines-webhook-deploy.yaml").spec.template.spec.affinity.nodeAffinity' $(CHART_DIR)/values.yaml
	yq -i 'del(.spec.template.spec.affinity.nodeAffinity)' $(CHART_DIR)/templates/tekton-pipelines-webhook-deploy.yaml
	yq -i '.controller.affinity.nodeAffinity = load("$(CHART_DIR)/templates/tekton-pipelines-controller-deploy.yaml").spec.template.spec.affinity.nodeAffinity' $(CHART_DIR)/values.yaml
	yq -i 'del(.spec.template.spec.affinity.nodeAffinity)' $(CHART_DIR)/templates/tekton-pipelines-controller-deploy.yaml

fetch-pipeline:: .kustomize-pipeline

# Add extra templates
fetch-pipeline::
	cp src/templates/* ${CHART_DIR}/templates

#############
# Operator
#############

fetch-operator: CHART_DIR:=charts/tekton-operator
ifeq ($(OPERATOR_VERSION),latest)
fetch-operator:: MANIFEST_URL:=https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml
else
fetch-operator:: MANIFEST_URL:=https://storage.googleapis.com/tekton-releases/operator/previous/v${OPERATOR_VERSION}/release.yaml
endif

fetch-operator:: .import-templates-trigger .update-app-version-dashboard

fetch-operator::
	# Remove tekton-operator-ns.yaml
	rm -r $(CHART_DIR)/templates/tekton-operator-ns.yaml
	# Move content of data: from config-logging-cm.yaml to loggingConfig: in values.yaml
	yq -i '.loggingConfig = load("$(CHART_DIR)/templates/config-logging-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/config-logging-cm.yaml

fetch-operator:: .kustomize-pipeline

#############
# Trigger
#############

fetch-trigger: CHART_DIR:=charts/tekton-trigger
ifeq ($(TRIGGER_VERSION),latest)
fetch-trigger:: MANIFEST_URL:=https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
else
fetch-trigger:: MANIFEST_URL:=https://storage.googleapis.com/tekton-releases/triggers/previous/v${TRIGGER_VERSION}/release.yaml
endif

fetch-trigger:: .import-templates-trigger .update-app-version-dashboard

# extract specific values
fetch-trigger::
	# Move content of data: from feature-flags-triggers-cm.yaml to featureFlags: in values.yaml
	yq -i '.featureFlags = load("$(CHART_DIR)/templates/feature-flags-triggers-cm.yaml").data' $(CHART_DIR)/values.yaml
	yq -i '.data = null' $(CHART_DIR)/templates/feature-flags-triggers-cm.yaml

fetch-trigger:: .kustomize-trigger

#############
# Dashboard
#############

fetch-dashboard:: CHART_DIR:=charts/tekton-dashboard
ifeq ($(DASHBOARD_VERSION),latest)
fetch-dashboard:: MANIFEST_URL:=https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
else
fetch-dashboard:: MANIFEST_URL:=https://storage.googleapis.com/tekton-releases/dashboard/previous/v${DASHBOARD_VERSION}/release.yaml
endif

fetch-dashboard:: .import-templates-dashboard .update-app-version-dashboard

fetch-dashboard::
	# Patch deployment command line args:
	# --pipelines-namespace=tekton-pipelines
	# --triggers-namespace=tekton-pipelines
	sed -i 's/-namespace=tekton-pipelines/-namespace={{ .Release.Namespace }}/g' ${CHART_DIR}/templates/tekton-dashboard-deploy.yaml

##########################
# Chart processing rules
##########################

.import-templates-%:
	rm -f ${CHART_DIR}/templates/*.yaml
	mkdir -p ${CHART_DIR}/templates
	curl -sS ${MANIFEST_URL} > ${CHART_DIR}/templates/resource.yaml

	# Split the resources into separate files
	jx gitops split -d ${CHART_DIR}/templates
	jx gitops rename -d ${CHART_DIR}/templates

	# Remove namespace from metadata to force with helm install
	find $(CHART_DIR)/templates -type f -name "*.yaml" -exec yq -i eval 'del(.metadata.namespace)' "{}" \;

	# amend remaining namespace: tekton-pipelines to  with release.namespace
	find $(CHART_DIR)/templates -type f -name "*.yaml" -exec sed -i "s/ namespace:.*/ namespace: '{{ .Release.Namespace }}'/" {} \;

.update-app-version-%:
	# update appVersion
	export APP_VERSION=`yq -r .data.version ${CHART_DIR}/templates/*-info-cm.yaml| sed 's/^v//'`; \
	yq -i '.appVersion=env(APP_VERSION)' ${CHART_DIR}/Chart.yaml; \

.kustomize-%:
	# kustomize the resources to include some helm template blocs
	kustomize build ${CHART_DIR} > ${CHART_DIR}/templates/resource.yaml && sed -i '/helmTemplateRemoveMe/d' ${CHART_DIR}/templates/resource.yaml
	jx gitops split -d ${CHART_DIR}/templates
	jx gitops rename -d ${CHART_DIR}/templates

refetch:
	export CHART_VERSION=`yq .appVersion ${CHART_DIR}/Chart.yaml` && \
		make fetch

######################
# Release management
######################

version:
	# Increment Chart.yaml version for minor changes to helm chart
	yq eval '.version = "$(RELEASE_VERSION)"' -i charts/tekton-pipeline/Chart.yaml

build: build-pipeline build-trigger build-dashboard build-operator

build-pipeline:: CHART_DIR:=charts/tekton-pipeline
build-operator:: CHART_DIR:=charts/tekton-operator
build-trigger:: CHART_DIR:=charts/tekton-trigger
build-dashboard:: CHART_DIR:=charts/tekton-dashboard

build-%::
	export CHART_DIR=charts/tekton-$(subst build-,,$@) && \
	helm dependency build $$CHART_DIR && \
	helm lint $$CHART_DIR && \
	helm package $$CHART_DIR

install-operator: clean build-operator
	helm upgrade --install --namespace tekton-operator --create-namespace tekton-operator charts/tekton-operator

uninstall-operator:
	helm uninstall --namespace tekton-operator tekton-operator

install: clean build
	helm upgrade --install --namespace tekton-pipelines-test --create-namespace tekton-pipeline charts/tekton-pipeline
	helm upgrade --install --namespace tekton-pipelines-test --create-namespace tekton-trigger charts/tekton-trigger
	helm upgrade --install --namespace tekton-pipelines-test --create-namespace tekton-dashboard charts/tekton-dashboard

uninstall:
	helm uninstall --namespace tekton-pipelines-test tekton-pipeline
	helm uninstall --namespace tekton-pipelines-test tekton-trigger
	helm uninstall --namespace tekton-pipelines-test tekton-dashboard

delete:
	helm delete --purge ${NAME}

clean:
	rm -rf tekton-*.tgz
	git clean -xdf charts/tekton-*

release: clean
	helm dependency build
	helm lint
	helm package .
	helm repo add jx-labs $(CHART_REPO)
	helm gcs push ${NAME}*.tgz jx-labs --public
	rm -rf ${NAME}*.tgz%

publish:: clean build
	cp tekton-*.tgz ${PAGES_REPO}

publish:: index

index:
	helm repo index --url https://eagafonov.github.io/tekton-helm-chart ${PAGES_REPO}

test:
	cd tests && go test -v

test-regen:
	cd tests && export HELM_UNIT_REGENERATE_EXPECTED=true && go test -v

verify:
	jx kube test run
