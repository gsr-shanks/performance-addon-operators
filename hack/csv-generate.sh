#!/bin/bash

set -e

GOROOT=$(go env GOROOT)
export GOROOT

OLD="4.4.0"
PREV="4.5.0"
LATEST="4.6.0"
LATEST_CHANNEL="4.6"
CSV_SKIP_RANGE=">=${PREV} <${LATEST}"

IS_DEV=$([[ $1 == "-dev" ]] && echo true || echo false)

if [[ -z "$CSV_VERSION" ]]; then
  CSV_VERSION=$LATEST
fi

if [[ -z "$CSV_CHANNEL" ]]; then
  CSV_CHANNEL=$LATEST_CHANNEL
fi

PACKAGE_NAME="performance-addon-operator"
PACKAGE_DIR="deploy/olm-catalog/${PACKAGE_NAME}"

CSV_DIR="${PACKAGE_DIR}/${CSV_VERSION}"

OUT_ROOT="build/_output"
OUT_DIR="${OUT_ROOT}/olm-catalog"
OUT_CSV_DIR="${OUT_DIR}/${PACKAGE_NAME}/${CSV_VERSION}"
OUT_CSV_FILE="${OUT_DIR}/${CSV_VERSION}/${PACKAGE_NAME}.clusterserviceversion.yaml"

TEMPLATES_DIR="${OUT_ROOT}/templates"
CSV_TEMPLATE_FILE="${TEMPLATES_DIR}/${PACKAGE_NAME}.v${CSV_VERSION}.clusterserviceversion.yaml"

EXTRA_ANNOTATIONS=""
MAINTAINERS=""

if [ -n "$MAINTAINERS_FILE" ]; then
  MAINTAINERS="-maintainers-from=$MAINTAINERS_FILE"
fi
if [ -n "$ANNOTATIONS_FILE" ]; then
  EXTRA_ANNOTATIONS="-annotations-from=$ANNOTATIONS_FILE"
fi

clean_package() {
  mkdir -p "$CSV_DIR"
  rm -rf "$OUT_DIR"
  mkdir -p "$OUT_CSV_DIR"

  rm -rf "${TEMPLATES_DIR}"
  mkdir -p "${TEMPLATES_DIR}"
}

if ! [[ "$CSV_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "CSV_VERSION not provided or does not match semver format"
  exit 1
fi

# clean up all old data first
clean_package

# do not generate new CRD/CSV for old versions
if [[ "$CSV_VERSION" != "$PREV" ]] && [[ "$CSV_VERSION" != "$OLD" ]]; then
  cp -a deploy/olm-catalog build/_output

  # generate a temporary csv we'll use as a template
  $KUSTOMIZE build config/default | $OPERATOR_SDK generate packagemanifests \
    --version="${CSV_VERSION}" \
    --channel="${CSV_CHANNEL}" \
    --default-channel=true \
    --update-objects \
    --from-version="${CSV_FROM_VERSION}" \
    --deploy-dir="deploy/olm-catalog"   \
    --output-dir="${OUT_DIR}" \
    --crds-dir="config/crd/bases"

  # copy template CSV file to preserve it for our csv-generator
  mv "${OUT_CSV_FILE}" "${CSV_TEMPLATE_FILE}"

  # copy the CRD before the generator will delete it
  cp "${OUT_DIR}/${CSV_VERSION}/performance.openshift.io_performanceprofiles.yaml" \
     "${CSV_DIR}/performance.openshift.io_performanceprofiles_crd.yaml"

  # using the generated CSV, create the real CSV by injecting all the right data into it
  build/_output/bin/csv-generator \
    --csv-version "${CSV_VERSION}" \
    --operator-csv-template-file "${CSV_TEMPLATE_FILE}" \
    --operator-image "${FULL_OPERATOR_IMAGE}" \
    --olm-bundle-directory "${OUT_CSV_DIR}" \
    --replaces-csv-version "${REPLACES_CSV_VERSION}" \
    --skip-range "${CSV_SKIP_RANGE}" \
    "${MAINTAINERS}" \
    "${EXTRA_ANNOTATIONS}"

    # restore the deleted CRD
    cp "${CSV_DIR}/performance.openshift.io_performanceprofiles_crd.yaml" \
      "${OUT_CSV_DIR}/performance.openshift.io_performanceprofiles_crd.yaml"
fi

if [[ "$IS_DEV" == true ]]; then
  # copy generated CSV and CRD back to repository dir
  cp "${OUT_CSV_DIR}"/* "${CSV_DIR}/"

  # copy generated package yaml
  cp "${OUT_DIR}/${PACKAGE_NAME}/${PACKAGE_NAME}.package.yaml" ${PACKAGE_DIR}/
fi

echo "New OLM manifests created at ${OUT_DIR}"
