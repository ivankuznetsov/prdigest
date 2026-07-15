FROM ruby:3.3-alpine
RUN apk add --no-cache build-base git
WORKDIR /app
COPY . .
RUN bundle install --without development
ENTRYPOINT ["bundle", "exec", "prdigest"]
CMD ["run", "--config", "/etc/prdigest/config.yml"]
