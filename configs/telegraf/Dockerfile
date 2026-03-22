FROM telegraf:1.37.3

ARG GOVC_VERSION=0.46.3

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq && \
    rm -rf /var/lib/apt/lists/* && \
    GOVC_ARCH=$([ "$(dpkg --print-architecture)" = "amd64" ] && echo "x86_64" || echo "arm64") && \
    curl -fsSL "https://github.com/vmware/govmomi/releases/download/v${GOVC_VERSION}/govc_Linux_${GOVC_ARCH}.tar.gz" | \
    tar -xz -C /usr/local/bin govc && \
    chmod +x /usr/local/bin/govc

COPY vsphere-inventory.sh /etc/telegraf/vsphere-inventory.sh
RUN chmod +x /etc/telegraf/vsphere-inventory.sh
