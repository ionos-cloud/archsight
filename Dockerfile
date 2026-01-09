# Build stage
FROM ruby:4.0-alpine3.23 AS builder

RUN apk add --no-cache build-base git libffi-dev yaml-dev

WORKDIR /app
COPY . .

# Build and install the gem to default locations
RUN gem build archsight.gemspec && \
    gem install --no-document archsight-*.gem && \
    which archsight && \
    gem env

# Runtime stage
FROM ruby:4.0-alpine3.23

RUN apk add --no-cache graphviz

# Copy installed gems (includes gems and executables)
COPY --from=builder /usr/local/lib/ruby/gems /usr/local/lib/ruby/gems

RUN mkdir -p /resources

ENV ARCHSIGHT_RESOURCES_DIR=/resources
ENV APP_ENV=production
ENV GEM_HOME=/usr/local/lib/ruby/gems/4.0.0
ENV PATH="/usr/local/lib/ruby/gems/4.0.0/bin:${PATH}"

EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4567/ || exit 1

ENTRYPOINT ["archsight"]
CMD ["web", "--port", "4567"]
