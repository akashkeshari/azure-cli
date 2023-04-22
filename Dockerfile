#---------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

ARG PYTHON_VERSION="3.10"

FROM python:${PYTHON_VERSION}-alpine

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

# bash gcc make openssl-dev libffi-dev musl-dev - dependencies required for CLI
# openssh - included for ssh-keygen
# ca-certificates

# curl - required for installing jp
# jq - we include jq as a useful tool
# pip wheel - required for CLI packaging
# jmespath-terminal - we include jpterm as a useful tool
# libintl and icu-libs - required by azure devops artifact (az extension add --name azure-devops)

# We don't use openssl (3.0) for now. We only install it so that users can use it.
WORKDIR azure-cli
COPY . /azure-cli

ARG JP_VERSION="0.1.3"

# 1. Build packages and store in tmp dir
# 2. Install the cli and the other command modules that weren't included
RUN apk add --no-cache bash openssh ca-certificates jq curl openssl perl git zip \
 && apk add --no-cache --virtual .build-deps gcc make openssl-dev libffi-dev musl-dev linux-headers \
 && apk add --no-cache libintl icu-libs libc6-compat \
 && apk add --no-cache bash-completion \
 && update-ca-certificates \
 && curl -L https://github.com/jmespath/jp/releases/download/${JP_VERSION}/jp-linux-amd64 -o /usr/local/bin/jp \
 && chmod +x /usr/local/bin/jp \
 && ./scripts/install_full.sh \
 && python ./scripts/trim_sdk.py \
 && cat /azure-cli/az.completion > ~/.bashrc \
 && runDeps="$( \
    scanelf --needed --nobanner --recursive /usr/local \
        | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
        | sort -u \
        | xargs -r apk info --installed \
        | sort -u \
    )" \
 && apk add --virtual .rundeps $runDeps \
 && addgroup -g 12345 12345 \
 && adduser -D -G 12345 12345 \
 && su 12345 -c "az extension add --name connectedk8s" \
 && /usr/bin/curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
 && chmod +x ./kubectl  \
 &&  mv ./kubectl /usr/local/bin/kubectl \
 && /usr/bin/curl https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz --output helm-v3.6.3-linux-amd64.tar.gz \
 && tar -zxvf helm-v3.6.3-linux-amd64.tar.gz \
 && mv linux-amd64/helm /usr/bin/helm \
 && apk del openssh jq curl openssl perl git zip .build-deps gcc make openssl-dev libffi-dev musl-dev linux-headers libintl icu-libs libc6-compat bash-completion

WORKDIR /

# Remove CLI source code from the final image and normalize line endings.
RUN rm -rf ./azure-cli && \
    dos2unix /root/.bashrc /usr/local/bin/az

ENV AZ_INSTALLER=DOCKER
CMD bash
