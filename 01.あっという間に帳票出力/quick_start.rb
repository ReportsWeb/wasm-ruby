# frozen_string_literal: true
$stdout.sync = true
require 'json'
require 'net/http'
begin
  require 'webrick'
rescue LoadError
  puts 'webrick が要ります。先に「gem install webrick」を実行してください。'
  exit 1
end
# このファイルの場所。Windows の日本語の画面（コードページ 932）では、Ruby 3.3 の __dir__ と require_relative が
# 日本語のフォルダー名を「?」に崩して見つけられないため、UTF-8 の Dir.pwd から組み立てる。
APP_DIR = File.dirname(File.expand_path((__FILE__.encode(Encoding::UTF_8) rescue __FILE__), Dir.pwd))
require 'reports_web'

# Docker を使わずに `ruby quick_start.rb` だけで動かすための準備（Docker の中では何もしない）。
# - 製品（Runtime/reports.web）は、ZIP の並びのまま ../../../Runtime/reports.web にある。
# - PDF を作るエンジンは、REPORTS_ENGINE_URL が無ければ 127.0.0.1:3107。居なければ、PC の Node.js で子として起動する。
module LocalRun
  IN_DOCKER = File.file?('/app/reports.web/design/index.html')

  def self.find_reports_web
    return File.expand_path(ENV['REPORTS_WEB_ROOT']) if ENV['REPORTS_WEB_ROOT'].to_s != ''
    return '/app/reports.web' if IN_DOCKER
    dir = APP_DIR
    loop do
      candidate = File.join(dir, 'Runtime', 'reports.web')
      return candidate if File.file?(File.join(candidate, 'design', 'index.html'))
      parent = File.dirname(dir)
      return nil if parent == dir
      dir = parent
    end
  end

  def self.alive?(url)
    uri = URI(url + '/health')
    Net::HTTP.start(uri.host, uri.port, open_timeout: 1.5, read_timeout: 1.5) { |http| http.get(uri.path).code == '200' }
  rescue StandardError
    false
  end

  def self.find_node
    names = Gem.win_platform? ? ['node.exe'] : ['node']
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
      names.each { |name| path = File.join(dir.delete('"'), name); return path if File.file?(path) }
    end
    nil
  end

  def self.prepare_engine(reports_web)
    return ENV['REPORTS_ENGINE_URL'].chomp('/') if ENV['REPORTS_ENGINE_URL'].to_s != ''
    return 'http://engine:3107' if IN_DOCKER
    url = 'http://127.0.0.1:3107'
    return url if alive?(url)
    node = find_node
    unless node
      puts 'PDF の保存には Node.js か Docker が要ります（https://nodejs.org/）。プレビューはこのまま使えます。'
      return url
    end
    server = File.join(reports_web, 'server', 'server.mjs')
    env = { 'REPORTS_ENGINE_ROOT' => File.dirname(server), 'REPORTS_ENGINE_PORT' => '3107', 'REPORTS_ENGINE_HOST' => '127.0.0.1' }
    pid = Process.spawn(env, node, '--max-old-space-size=1024', server, out: File::NULL, err: File::NULL)
    at_exit { Process.kill('KILL', pid) rescue nil }
    60.times do
      return url if alive?(url)
      sleep 0.5
    end
    puts 'PDF 用のエンジンを起動できませんでした（3107 番が使用中かもしれません）。プレビューはこのまま使えます。'
    url
  end

  # 端末から起動したときだけ、ブラウザーで開く（REPORTS_NO_BROWSER=1 で止められる）。
  def self.open_browser(url)
    return if IN_DOCKER || !$stdout.tty? || ENV['REPORTS_NO_BROWSER']
    command = if Gem.win_platform? then ['rundll32', 'url.dll,FileProtocolHandler', url]
              elsif RUBY_PLATFORM.include?('darwin') then ['open', url]
              else ['xdg-open', url]
              end
    Process.detach(Process.spawn(*command, out: File::NULL, err: File::NULL)) rescue nil
  end
end

app = LocalRun::IN_DOCKER ? '/app' : APP_DIR
reports_web = LocalRun.find_reports_web
unless reports_web
  puts 'Runtime/reports.web が見つかりません。ZIP を展開したフォルダーの並びのまま動かしてください。'
  exit 1
end
engine = LocalRun.prepare_engine(reports_web)

definition = JSON.parse(File.read(File.join(app, 'definition', 'quick-report.prepdj'), encoding: 'UTF-8'))
print_data = PaoReportsWeb::PrintData.new
  .set_definition(definition).page_start
  .set_value('Title', 'あっという間に帳票出力')
  .set_value('CustomerName', '株式会社パオ').page_end.to_json

# Docker の中では 8080 番。外では 127.0.0.1 の 19260 番（compose と同じ番号）。
port = Integer(ENV.fetch('PORT', LocalRun::IN_DOCKER ? '8080' : '19260'))
server = WEBrick::HTTPServer.new(Port: port, BindAddress: LocalRun::IN_DOCKER ? '0.0.0.0' : '127.0.0.1', Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN), AccessLog: [])
server.mount_proc('/') { |_req, res| res['Content-Type'] = 'text/html; charset=utf-8'; res.body = File.binread(File.join(app, 'index.html')) }
server.mount_proc('/print-data') { |_req, res| res['Content-Type'] = 'application/json'; res.body = print_data }
server.mount_proc('/pdf') do |req, res|
  begin
    res['Content-Type'] = 'application/pdf'
    res.body = PaoReportsWeb::ReportsWebEngine.new(url: engine).render_pdf(req.body.to_s)
  rescue PaoReportsWeb::ReportsWebEngineError
    res.status = 502; res.body = 'PDF engine request failed'
  end
end
server.mount('/reports.web', WEBrick::HTTPServlet::FileHandler, reports_web)
server.mount('/demo/reports.web', WEBrick::HTTPServlet::FileHandler, reports_web)
trap('TERM') { server.shutdown }; trap('INT') { server.shutdown }
unless LocalRun::IN_DOCKER
  url = "http://127.0.0.1:#{port}/"
  puts "見本の帳票：#{url}（止めるときは Ctrl+C）"
  LocalRun.open_browser(url)
end
server.start
