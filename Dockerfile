# Build stage
FROM ruby:4.0-alpine3.23 AS builder

RUN apk add --no-cache build-base git libffi-dev yaml-dev

WORKDIR /app
COPY . .

# Build and install the gem
RUN gem build archsight.gemspec && \
    gem install --no-document archsight-*.gem && \
    echo "=== Builder: which archsight ===" && \
    which archsight && \
    echo "=== Builder: gem env ===" && \
    gem env && \
    echo "=== Builder: /usr/local/bundle contents ===" && \
    ls -la /usr/local/bundle/ && \
    echo "=== Builder: /usr/local/bundle/gems ===" && \
    ls -la /usr/local/bundle/gems/

# Runtime stage
FROM ruby:4.0-alpine3.23

RUN apk add --no-cache graphviz

# Copy installed gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

RUN echo "=== Runtime: gem env ===" && \
    gem env && \
    echo "=== Runtime: /usr/local/bundle contents ===" && \
    ls -la /usr/local/bundle/ && \
    echo "=== Runtime: /usr/local/bundle/gems ===" && \
    ls -la /usr/local/bundle/gems/ && \
    echo "=== Runtime: which archsight ===" && \
    which archsight && \
    echo "=== Runtime: archsight version test ===" && \
    archsight version

RUN mkdir -p /resources

ENV ARCHSIGHT_RESOURCES_DIR=/resources
ENV APP_ENV=production

EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4567/ || exit 1

ENTRYPOINT ["archsight"]
CMD ["web", "--port", "4567"]
