FROM ubuntu:18.04

MAINTAINER Florian Finke <florian@finke.email>

# tools installed below may need these for their installations
ENV LANG=en_US.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONIOENCODING=UTF-8

RUN set -ex \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    # install curl and its recommendations (HTTPs support, etc)
    && apt-get install -y curl \
    && curl -sL https://deb.nodesource.com/setup_12.x > setup-node.sh \
    && bash setup-node.sh \
    && rm setup-node.sh \
    && apt-get install --no-install-recommends --fix-missing -y \
        build-essential \
        curl \
        git \
        libbz2-dev \
        libffi-dev \
        libfontconfig \
        libjpeg-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl1.0-dev \
        libxml2-dev \
        libxslt1-dev \
        locales \
        make \
        nodejs \
        openssh-client \
        python3-dev \
        python3-lxml \
        python3-pil \
        rsync \
        ruby-dev \
        rubygems \
        zlib1g-dev \
    && echo -e "Host *\n\tStrictHostKeyChecking no\n\n" > /etc/ssh/ssh_config \
    # Install the most up to date pip (This will include setuptools)
    && curl -sL https://bootstrap.pypa.io/get-pip.py > get-pip.py \
    && python3 get-pip.py \
    && rm get-pip.py \
    # install global tools
    && pip3 install --upgrade tox tox-pyenv awscli awsebcli \
    && npm install -g npm@latest yarn \
    # clean caches
    && apt-get autoremove -y \
    && apt-get clean all \
    && rm -rf /var/lib/apt/lists/* \
    # generate locale
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8

ARG PYENV_EXTRA_PYTHON_VERSIONS
ARG PYENV_UPDATED_AT
RUN if [ -z "$PYENV_UPDATED_AT" ]; then \
        echo >&2 'Build with docker build argument --build-arg=PYENV_UPDATED_AT=$(date -u +%Y-%m-%d)'; \
        exit 1; \
    fi
ENV PYENV_UPDATED_AT=$PYENV_UPDATED_AT

# pyenv ENV VARS
ENV PYENV_ROOT /pyenv
ENV PATH /pyenv/shims:/pyenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PYENV_INSTALLER_ROOT /pyenv-installer
ENV PYENV_REQUIRED_PYTHON_BASENAME python_versions.txt
ENV PYENV_REQUIRED_PYTHON /pyenv-config/$PYENV_REQUIRED_PYTHON_BASENAME

# setup Python versions
RUN set -ex \
    && git clone https://github.com/pyenv/pyenv.git $PYENV_ROOT \
    && PYENV_BUILD_ROOT=/pyenv/plugins/python-build \
    # hardcode Python 2.7 + find unique major.minor versions > 2.7
    && PYTHON_VERSIONS="2.7 $(\
        $PYENV_BUILD_ROOT/bin/python-build --definitions \
            | grep -E '^[0-9]' \
            | grep -v -e '-dev$' -e '^2' \
            | grep -oE '^[0-9]+\.[0-9]+' \
            | sort -u \
            | xargs)" \
    # find the most recent point version and link it as the major.minor, and install
    && for version in $PYTHON_VERSIONS; do \
        actual=$($PYENV_BUILD_ROOT/bin/python-build --definitions \
            | grep -E '^[0-9]' \
            | grep -v -e '-dev$' \
            | grep -F $version. \
            | sort -rn -t. -k3,3 \
            | head -n 1) \
        && pyenv install $actual || exit 1 \
        && ln -s $actual $PYENV_ROOT/versions/$version; \
    done \
    # add extra Python versions specified as build arguments
    && test -z "$PYENV_EXTRA_PYTHON_VERSIONS" \
    || for version in $PYENV_EXTRA_PYTHON_VERSIONS; do \
        PYTHON_VERSIONS="$PYTHON_VERSIONS $version" \
        && pyenv install -s $version || exit 1; \
    done \
    && mkdir -p $(dirname $PYENV_REQUIRED_PYTHON) \
    && PYTHON_VERSIONS="$(echo "$PYTHON_VERSIONS" \
        | tr ' ' '\n' \
        | sort -u \
        | sort -n -t. -k1,1 -k2,2)" \
    && echo "$PYTHON_VERSIONS" > $PYENV_REQUIRED_PYTHON \
    # set the most recent Python version as the default (order matters)
    && echo "$PYTHON_VERSIONS" | tac | xargs pyenv global

ENTRYPOINT ["/bin/sh", "-c", "export PYTHON_VERSIONS=\"$(cat $PYENV_REQUIRED_PYTHON)\" && exec \"$@\"", "-"]
CMD ["/bin/bash"]
