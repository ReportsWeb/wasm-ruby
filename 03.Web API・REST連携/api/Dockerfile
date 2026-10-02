FROM ruby:3.3-slim-bookworm AS gems
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev && rm -rf /var/lib/apt/lists/*
ENV BUNDLE_WITHOUT=development:test BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/bundle
WORKDIR /opt/reports
COPY Gemfile Gemfile.lock ./
RUN bundle install

FROM ruby:3.3-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 --home /nonexistent --shell /usr/sbin/nologin reports
ENV BUNDLE_WITHOUT=development:test BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/bundle
WORKDIR /opt/reports
COPY --from=gems /bundle /bundle
COPY Gemfile Gemfile.lock app.rb config.ru ./
COPY lib ./lib
COPY public ./public
COPY resources ./resources
USER reports
ENV HOST=0.0.0.0 PORT=8080 REPORTS_RESOURCE_ROOT=/opt/reports/resources REPORTS_TEMPLATE=/opt/reports/public/index.html REPORTS_WEB_ROOT=/opt/reports/web
EXPOSE 8080
CMD ["bundle","exec","puma","-b","tcp://0.0.0.0:8080","config.ru"]
