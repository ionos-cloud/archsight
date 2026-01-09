# Build stage
FROM ruby:4.0-alpine3.23 AS builder

RUN apk add --no-cache build-base git libffi-dev yaml-dev

WORKDIR /app
COPY archsight.gemspec Gemfile Gemfile.lock* .ruby-version ./
COPY lib/archsight/version.rb lib/archsight/version.rb
RUN bundle config set --local deployment true && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

COPY . .

# Runtime stage
FROM ruby:4.0-alpine3.23

RUN apk add --no-cache graphviz

WORKDIR /app
COPY --from=builder /app /app
COPY --from=builder /usr/local/bundle /usr/local/bundle

RUN mkdir -p /resources

ENV ARCHSIGHT_RESOURCES_DIR=/resources
ENV APP_ENV=production

EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4567/ || exit 1

ENTRYPOINT ["bundle", "exec", "exe/archsight"]
CMD ["web", "--port", "4567"]
