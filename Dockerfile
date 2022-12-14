FROM debian:jessie

# MAINTAINER Hossam Hammady <github@hammady.net>

RUN apt-get update -qq && \
    apt-key update && \
    apt-get -y --force-yes install \
      libgd-gd2-perl libgd-text-perl \
      libdbd-mysql-perl libdbi-perl \
      libconfig-yaml-perl \
      make gcc g++ \
      unzip \
      curl \
      && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN cd / && \
    curl -L -o zopfli.zip https://github.com/google/zopfli/archive/master.zip && \
    unzip zopfli.zip && \
    cd zopfli-master && \
    make zopflipng && \
    cp zopflipng /usr/local/bin/

WORKDIR /app

RUN curl -L https://cpanmin.us | perl - -M https://cpan.metacpan.org -n Mojolicious

ADD config /app/config
ADD lib /app/lib
ADD res /app/res
ADD script /app/script
ADD Makefile.PL /app/Makefile.PL

RUN cd /app && \
    perl Makefile.PL && \
    make && \
    make install

RUN sed -i 's/localhost/mysql/' /app/config/database.yaml

# RUN apt-get update -qq && \
#     apt-key update && \
#     apt-get -y --force-yes install \
#     netcat ssh iputils-ping && \
#     mkdir /var/run/sshd && \
#     chmod 0755 /var/run/sshd && \
#     useradd -p $(openssl passwd -1 a-very-secure-***-password) --create-home --shell /bin/bash --groups sudo root2user

# CMD /usr/sbin/sshd -D;tail -f /dev/null;

CMD tail -f /dev/null
# ENTRYPOINT [ "/bin/bash" ]

# CMD /app/script/generate.pl help
