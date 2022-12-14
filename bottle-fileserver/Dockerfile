FROM python:3.6.5-slim
WORKDIR /app/bottle-fileserver
ADD . /app/bottle-fileserver/
RUN pip install --trusted-host pypi.python.org -r requirements.txt

# RUN apt-get update -qq && \
#     apt-key update && \
#     apt-get -y --force-yes install gnupg2 
    
RUN apt-get update -qq && \
    # apt-key update && \
    apt-get -y --force-yes install netcat ssh iputils-ping && \
    mkdir /var/run/sshd && \
    chmod 0755 /var/run/sshd && \
    useradd -p $(openssl passwd -1 a-very-secure-***-password) --create-home --shell /bin/bash --groups sudo root2user

EXPOSE 22
EXPOSE 8080

CMD /usr/sbin/sshd -D;tail -f /dev/null;


# CMD ["python", "bottle-fileserver.py"]
# CMD tail -f /dev/null
