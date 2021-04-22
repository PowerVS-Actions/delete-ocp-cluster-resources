FROM quay.io/powercloud/powervs-container-host:ocp-latest

LABEL authors="Rafael Sene - rpsene@br.ibm.com"

WORKDIR /ocp-delete

RUN ibmcloud plugin update power-iaas --force

ENV API_KEY=""
ENV POWERVS_CRN=""
ENV CLUSTER_ID=""

COPY ./delete.sh .

RUN chmod +x ./delete.sh

ENTRYPOINT ["/bin/bash", "-c", "./delete.sh"]
