FROM ruby:3.3-alpine
RUN gem install webrick --no-document && gem install reports_web -v 1.0.0 --no-document
WORKDIR /app
COPY quick_start.rb index.html ./
COPY definition /app/definition
ENTRYPOINT ["ruby", "/app/quick_start.rb"]
