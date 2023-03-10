# Cross Container Args
ARG ALPINE_VERSION=3.17.0
ARG NGINX_VERSION=1.23.3
ARG NGINX_RTMP_MODULE_VERSION=1.2.2
ARG FFMPEG_VERSION=5.1
ARG SOURCE_DIR=/usr/local/src
ARG MAKEFLAGS="-j4"

FROM phpswoole/swoole:php8.1-alpine as swoole
ARG APP_DIR=/app

ENV TESTING=false

WORKDIR ${APP_DIR}

COPY app/composer.json ${APP_DIR}
COPY app/composer.lock ${APP_DIR}

RUN composer install \
      --ignore-platform-reqs \
      --optimize-autoloader \
      --no-plugins \
      --no-scripts \
      --prefer-dist

FROM alpine:${ALPINE_VERSION} as nginx

ARG NGINX_VERSION
ARG NGINX_RTMP_MODULE_VERSION
ARG SOURCE_DIR
ARG MAKEFLAGS

# Dependencies
RUN apk add --no-cache \
  build-base \
  ca-certificates \
  curl \
  gcc \
  libc-dev \
  libgcc \
  linux-headers \
  make \
  musl-dev \
  openssl \
  openssl-dev \
  pcre \
  pcre-dev \
  pkgconf \
  pkgconfig \
  zlib-dev

# Create source directory
RUN mkdir -p ${SOURCE_DIR}


# DOWNLOAD
WORKDIR ${SOURCE_DIR}

## nginx
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
    && tar -zxf nginx-${NGINX_VERSION}.tar.gz \
    && rm nginx-${NGINX_VERSION}.tar.gz

## rtmp module
RUN wget https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_MODULE_VERSION}.tar.gz \
    && tar -zxf v${NGINX_RTMP_MODULE_VERSION}.tar.gz \
    && rm v${NGINX_RTMP_MODULE_VERSION}.tar.gz


# COMPILE
WORKDIR ${SOURCE_DIR}/nginx-${NGINX_VERSION}

## Nginx with RTMP module
RUN ./configure \
    --prefix=/usr/local/nginx \
    --add-module=${SOURCE_DIR}/nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION} \
    --conf-path=/etc/nginx/nginx.conf \
    --with-threads \
    --with-file-aio \
    --with-http_ssl_module \
    --with-debug \
    --with-http_stub_status_module \
    --with-cc-opt="-Wimplicit-fallthrough=0" \
  && make \
  && make install

## Nginx copy configs
RUN cp ${SOURCE_DIR}/nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION}/stat.xsl /usr/local/nginx/html/stat.xsl \
    && rm -rf ${SOURCE_DIR} \
    && mkdir /var/run/stunnel4


FROM alpine:${ALPINE_VERSION} as ffmpeg
ARG FFMPEG_VERSION
ARG SOURCE_DIR
ARG MAKEFLAGS
ARG PREFIX=/usr/local

# Dependencies
RUN apk add --no-cache \
  build-base \
  coreutils \
  freetype-dev \
  lame-dev \
  libogg-dev \
  libass \
  libass-dev \
  libvpx-dev \
  libvorbis-dev \
  libwebp-dev \
  libtheora-dev \
  openssl-dev \
  opus-dev \
  pkgconf \
  pkgconfig \
  rtmpdump-dev \
  wget \
  x264-dev \
  x265-dev \
  yasm

RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories
RUN apk add --no-cache fdk-aac-dev

# Create source directory
RUN mkdir -p ${SOURCE_DIR}


# DOWNLOAD
WORKDIR ${SOURCE_DIR}


## ffmpeg
RUN wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz \
    && tar -zxf ffmpeg-${FFMPEG_VERSION}.tar.gz \
    && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# COMPILE
WORKDIR ${SOURCE_DIR}/ffmpeg-${FFMPEG_VERSION}

RUN ./configure \
    --prefix=${PREFIX} \
    --enable-version3 \
    --enable-gpl \
    --enable-nonfree \
    --enable-small \
    --enable-libmp3lame \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libopus \
    --enable-libfdk-aac \
    --enable-libass \
    --enable-libwebp \
    --enable-postproc \
    --enable-libfreetype \
    --enable-openssl \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --extra-libs="-lpthread -lm" \
  && make \
  && make install \
  && make distclean \
  && rm -rf /var/cache/* /tmp/*

FROM alpine:${ALPINE_VERSION} as final
LABEL MAINTAINER Wess Cope <wess@appwrite.io>

ARG PHP_INI_DIR=/etc/php81

# Set default ports.
ENV HTTP_PORT 8000
ENV HTTPS_PORT 443
ENV RTMP_PORT 1935

RUN apk add --no-cache \
  ca-certificates \
  gettext \
  openssl \
  pcre \
  lame \
  libogg \
  curl \
  libass \
  libvpx \
  libvorbis \
  libwebp \
  libtheora \
  opus \
  rtmpdump \
  x264-dev \
  x265-dev \
  php81 \
  php81-ctype \
  php81-curl \
  php81-dom \
  php81-fpm \
  php81-gd \
  php81-intl \
  php81-mbstring \
  php81-mysqli \
  php81-opcache \
  php81-openssl \
  php81-phar \
  php81-session \
  php81-xml \
  php81-xmlreader \
  php81-pecl-swoole \
  php81-pecl-swoole-dev \
  composer

COPY --from=nginx /usr/local/nginx /usr/local/nginx
COPY --from=nginx /etc/nginx /etc/nginx
COPY --from=ffmpeg /usr/local /usr/local
COPY --from=ffmpeg /usr/lib/libfdk-aac.so.2 /usr/lib/libfdk-aac.so.2

RUN echo "opcache.enable_cli=1" >> $PHP_INI_DIR/php.ini
RUN echo "memory_limit=1024M" >> $PHP_INI_DIR/php.ini

# Add NGINX path, config and static files.
ENV PATH "${PATH}:/usr/local/nginx/sbin"

COPY nginx.conf /etc/nginx/nginx.conf.template

RUN mkdir -p /opt/data && mkdir /www

COPY static /www/static
COPY app /app

EXPOSE 1935
EXPOSE 8000
EXPOSE 3000

RUN envsubst "$(env | sed -e 's/=.*//' -e 's/^/\$/g')" < \
      /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

ENV TERM xterm-256color

CMD ["/bin/sh"]