#!/usr/bin/env bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${script_dir}/../../scripts/lib.sh"

readonly kernel_builder="${repo_root_dir}/tools/packaging/kernel/build-kernel.sh"

GO_VERSION=${GO_VERSION}
RUST_VERSION=${RUST_VERSION:-}

DESTDIR=${DESTDIR:-${PWD}}
PREFIX=${PREFIX:-/opt/kata}
container_image="${SHIM_V2_CONTAINER_BUILDER:-$(get_shim_v2_image_name)}"

EXTRA_OPTS="${EXTRA_OPTS:-""}"
VMM_CONFIGS="qemu fc"
REMOVE_VMM_CONFIGS="${REMOVE_VMM_CONFIGS:-""}"

sudo docker pull ${container_image} || \
	(sudo docker build \
		--build-arg GO_VERSION="${GO_VERSION}" \
	      	--build-arg RUST_VERSION="${RUST_VERSION}" \
		-t "${container_image}" "${script_dir}" && \
	 # No-op unless PUSH_TO_REGISTRY is exported as "yes"
	 push_to_registry "${container_image}")

arch=$(uname -m)
if [ ${arch} = "ppc64le" ]; then
	arch="ppc64"
fi

if [ -n "${RUST_VERSION}" ]; then
	sudo docker run --rm -i -v "${repo_root_dir}:${repo_root_dir}" \
		-w "${repo_root_dir}/src/runtime-rs" \
		"${container_image}" \
		bash -c "git config --global --add safe.directory ${repo_root_dir} && make PREFIX=${PREFIX} QEMUCMD=qemu-system-${arch}"

	sudo docker run --rm -i -v "${repo_root_dir}:${repo_root_dir}" \
		-w "${repo_root_dir}/src/runtime-rs" \
		"${container_image}" \
		bash -c "git config --global --add safe.directory ${repo_root_dir} && make PREFIX="${PREFIX}" DESTDIR="${DESTDIR}" install"
fi
	
sudo docker run --rm -i -v "${repo_root_dir}:${repo_root_dir}" \
	-w "${repo_root_dir}/src/runtime" \
	"${container_image}" \
	bash -c "git config --global --add safe.directory ${repo_root_dir} && make PREFIX=${PREFIX} QEMUCMD=qemu-system-${arch} ${EXTRA_OPTS}"

sudo docker run --rm -i -v "${repo_root_dir}:${repo_root_dir}" \
	-w "${repo_root_dir}/src/runtime" \
	"${container_image}" \
	bash -c "git config --global --add safe.directory ${repo_root_dir} && make PREFIX="${PREFIX}" DESTDIR="${DESTDIR}"  ${EXTRA_OPTS} install"

for vmm in ${VMM_CONFIGS}; do
	config_file="${DESTDIR}/${PREFIX}/share/defaults/kata-containers/configuration-${vmm}.toml"
	if [ -f ${config_file} ]; then
		sudo sed -i -e '/^initrd =/d' ${config_file}
	fi
done

for vmm in ${REMOVE_VMM_CONFIGS}; do
	sudo rm -f "${DESTDIR}/${PREFIX}/share/defaults/kata-containers/configuration-$vmm.toml"
done

pushd "${DESTDIR}/${PREFIX}/share/defaults/kata-containers"
	sudo ln -sf "configuration-qemu.toml" configuration.toml
popd
