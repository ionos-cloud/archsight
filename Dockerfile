FROM ruby:4.0-alpine3.23

# Install system dependencies required for building gems
RUN apk add --no-cache \
    build-base \
    git \
    libffi-dev \
    yaml-dev \
    graphviz

# Set working directory
WORKDIR /app

# Copy gemspec, Gemfile, and .ruby-version for dependency installation
COPY archsight.gemspec Gemfile Gemfile.lock* .ruby-version ./
COPY lib/archsight/version.rb lib/archsight/version.rb

# Install Ruby dependencies
RUN bundle install --jobs 4

# Copy application code
COPY . .

# Create volume mount point for resources
RUN mkdir -p /resources

# Set resources directory environment variable
ENV ARCHSIGHT_RESOURCES_DIR=/resources
ENV APP_ENV=production

# Expose port for web server
EXPOSE 4567

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4567/ || exit 1

# Default command - use the archsight CLI
CMD ["bundle", "exec", "exe/archsight", "web", "--port", "4567"]
