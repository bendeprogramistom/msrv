# ################
# 1st Stage: Use openjdk 8 to verify signature w/ jarsigner
# ################
FROM openjdk:8-jdk AS download_verification

RUN apt-get -q update && \
		apt-get install -qy wget && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* && \
        rm -rf /tmp/*

ARG MID_INSTALLATION_URL=https://install.service-now.com/glide/distribution/builds/package/app-signed/mid/2022/09/16/mid.tokyo-07-08-2022__patch1-09-01-2022_09-16-2022_1610.linux.x86-64.zip
ARG MID_INSTALLATION_FILE
ARG MID_SIGNATURE_VERIFICATION="TRUE"

WORKDIR /opt/midserver/

COPY asset/*.zip asset/download.sh asset/validate_signature.sh ./

# download.sh and validate_signature.sh
RUN chmod 6750 /opt/midserver/*.sh

RUN echo "Check MID installer URL: ${MID_INSTALLATION_URL} or Local installer: ${MID_INSTALLATION_FILE}"

# Download the installation ZIP file or using the local one
RUN if [ -z "$MID_INSTALLATION_FILE" ] ; \
    then /opt/midserver/download.sh $MID_INSTALLATION_URL ; \
    else echo "Use local file: $MID_INSTALLATION_FILE" && ls -alF /opt/midserver/ && mv /opt/midserver/$MID_INSTALLATION_FILE /tmp/mid.zip ; fi

# Verify mid.zip signature
RUN if [ "$MID_SIGNATURE_VERIFICATION" = "TRUE" ] ; \
    then echo "Verify the signature of the installation file" && /opt/midserver/validate_signature.sh /tmp/mid.zip; \
    else echo "Skip signature validation of the installation file "; fi

RUN unzip -d /opt/midserver/ /tmp/mid.zip && rm -f /tmp/mid.zip

# ################
# Final Stage (using the downloaded ZIP file from previous stage)
# ################
FROM centos:centos7.9.2009

RUN yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

RUN yum update -y && \
	yum install -y  sysvinit-tools \
                    bind-utils \
                    xmlstarlet \
                    curl \
                    net-tools \
                    iputils &&\
    yum clean packages -y && \
    rm -rf /tmp/*

# ##########################
# Build argument definition
# ##########################


ARG MID_USERNAME=mid

ARG GROUP_ID=1001

ARG USER_ID=1001


# ############################
# Runtime Env Var Definition
# ############################

# Mandatory Env Var
ENV MID_INSTANCE_URL "" \
    MID_INSTANCE_USERNAME "" \
    MID_INSTANCE_PASSWORD "" \
    MID_SERVER_NAME "" \

# Optional Env Var
    MID_PROXY_HOST "" \
    MID_PROXY_PORT "" \
    MID_PROXY_USERNAME "" \
    MID_PROXY_PASSWORD "" \

    MID_SECRETS_FILE "" \
    MID_MUTUAL_AUTH_PEM_FILE ""


RUN if [[ -z "${GROUP_ID}" ]]; then GROUP_ID=1001; fi && \
		if [[ -z "${USER_ID}" ]]; then USER_ID=1001; fi && \
        echo "Add GROUP id: ${GROUP_ID}, USER id: ${USER_ID} for username: ${MID_USERNAME}"


RUN groupadd -g $GROUP_ID $MID_USERNAME && \
        useradd -c "MID container user" -r -m -u $USER_ID -g $MID_USERNAME $MID_USERNAME

# only copy needed scripts and .container
COPY asset/init asset/.container asset/check_health.sh /opt/midserver/

# 6:setuid + setgid, 750: a:rwx, g:rx, o:
RUN chmod 6750 /opt/midserver/* && chown -R $MID_USERNAME:$MID_USERNAME /opt/midserver/

# Copy agent/ from download_verification
COPY --chown=$MID_USERNAME:$MID_USERNAME  --from=download_verification /opt/midserver/agent/ /opt/midserver/agent/

# Check if the wrapper PID file exists and a HeartBeat is processed in the last 30 minutes
HEALTHCHECK --interval=5m --start-period=3m --retries=3 --timeout=15s \
    CMD bash check_health.sh || exit 1

WORKDIR /opt/midserver/

USER $MID_USERNAME

ENTRYPOINT ["/opt/midserver/init", "start"]
