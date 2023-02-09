#---------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

ARG PYTHON_VERSION="3.10"

#---------------------------------------------------------------------------------------------

FROM python:${PYTHON_VERSION}-alpine AS common

# bash gcc make openssl-dev libffi-dev musl-dev - dependencies required for CLI
# openssh - included for ssh-keygen
# ca-certificates

# curl - required for installing jp, and also a useful tool
# jq - we include jq as a useful tool
# libintl and icu-libs - required by azure devops artifact (az extension add --name azure-devops)

# We don't use openssl (3.0) for now. We only install it so that users can use it.
RUN apk add --no-cache \
    bash openssh ca-certificates jq curl openssl perl git zip \
    libintl icu-libs libc6-compat \
    bash-completion \
 && update-ca-certificates

#---------------------------------------------------------------------------------------------

FROM common AS tools

ARG JP_VERSION="0.1.3"

RUN curl -L https://github.com/jmespath/jp/releases/download/${JP_VERSION}/jp-linux-amd64 -o /usr/local/bin/jp \
 && chmod +x /usr/local/bin/jp

#---------------------------------------------------------------------------------------------

FROM common AS build

# bash gcc make openssl-dev libffi-dev musl-dev - dependencies required for CLI

RUN apk add --no-cache --virtual .build-deps gcc make openssl-dev libffi-dev musl-dev linux-headers

WORKDIR azure-cli
COPY . /azure-cli

# Remove CLI source code from the final image and normalize line endings.
RUN dos2unix ./src/azure-cli/az ./src/azure-cli/az.completion.sh

# Inlined wheel build of ./scripts/install_full.sh
RUN find src/ -name setup.py -type f \
    | xargs -I {} dirname {} \
    | grep -v azure-cli-testsdk \
    | xargs pip wheel --no-deps --wheel-dir=/whl \
 && pip wheel --wheel-dir=/whl -r ./src/azure-cli/requirements.$(python ./scripts/get-python-version.py).$(uname).txt

#---------------------------------------------------------------------------------------------

FROM common

ARG CLI_VERSION

# Metadata as defined at http://label-schema.org
ARG BUILD_DATE

LABEL maintainer="Microsoft" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.vendor="Microsoft" \
      org.label-schema.name="Azure CLI" \
      org.label-schema.version=$CLI_VERSION \
      org.label-schema.license="MIT" \
      org.label-schema.description="The Azure CLI is used for all Resource Manager deployments in Azure." \
      org.label-schema.url="https://docs.microsoft.com/cli/azure/overview" \
      org.label-schema.usage="https://docs.microsoft.com/cli/azure/install-az-cli2#docker" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/Azure/azure-cli.git" \
      org.label-schema.docker.cmd="docker run -v \${HOME}/.azure:/root/.azure -it mcr.microsoft.com/azure-cli:$CLI_VERSION"

COPY --from=tools /usr/local /usr/local

RUN --mount=from=build,source=/whl,target=/whl \
    pip install /whl/* \
 && find /usr/local -name __pycache__ | xargs -r rm -rf

RUN scanelf --needed --nobanner --recursive /usr/local \
    | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
    | sort -u \
    | xargs -r apk info --installed \
    | sort -u \
    | xargs -r apk add --virtual .rundeps \
 && ln -s /usr/local/bin/az.completion.sh /etc/profile.d/

ENV AZ_INSTALLER=DOCKER
CMD bash
