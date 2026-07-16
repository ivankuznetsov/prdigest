FROM ruby:3.4-alpine

RUN apk add --no-cache ca-certificates tzdata \
    && apk add --no-cache --virtual .build-deps build-base \
    && addgroup -S prdigest \
    && adduser -S -D -H -G prdigest prdigest \
    && install -d -m 0700 -o prdigest -g prdigest /var/lib/prdigest \
    && install -d -m 0750 -o root -g prdigest /etc/prdigest

WORKDIR /app
COPY Gemfile prdigest.gemspec ./
COPY lib ./lib
COPY exe ./exe
RUN bundle config set without development \
    && bundle install \
    && apk del .build-deps

USER prdigest
ENTRYPOINT ["bundle", "exec", "prdigest"]
CMD ["run", "--config", "/etc/prdigest/config.yml"]
