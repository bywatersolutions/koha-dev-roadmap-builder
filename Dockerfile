# Stage 1 - Build the static site assets
FROM perl:latest AS builder

ARG rt_url
ENV RT_URL=$rt_url
ARG rt_user
ENV RT_USER=$rt_user
ARG rt_pw
ENV RT_PW=$rt_pw
ARG koha_url
ENV KOHA_URL=$koha_url
ARG koha_user
ENV KOHA_USER=$koha_user
ARG koha_pw
ENV KOHA_PW=$koha_pw
ARG slack_url
ENV SLACK_URL=$slack_url

COPY . /usr/src/roadmap
WORKDIR /usr/src/roadmap

RUN cpanm --notest --installdeps .
RUN cpanm --notest https://github.com/kylemhall/BZ-Client-REST.git

RUN ./dev-roadmap-dashboard-builder.pl --rt-url=$RT_URL --rt-username=$RT_USER --rt-password=$RT_PW --community-url=$KOHA_URL --community-username=$KOHA_USER --community-password=$KOHA_PW -v

RUN /usr/local/bin/dapper build

RUN cd _output && rm Dockerfile cpanfile dev-roadmap-dashboard-builder.pl roadmap.png

# Stage 2 - Build web server image from statically build assets
FROM nginx:alpine
COPY --from=builder /usr/src/roadmap/_output/ /usr/share/nginx/html/
