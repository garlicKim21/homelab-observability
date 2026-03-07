FROM alpine:3.21
RUN apk add --no-cache rsyslog
COPY rsyslog.conf /etc/rsyslog.conf
CMD ["rsyslogd", "-n"]
