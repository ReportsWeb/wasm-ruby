# frozen_string_literal: true
require 'json'
require 'net/http'
require 'webrick'
require 'reports_web'

definition = JSON.parse(File.read('/app/definition/quick-report.prepdj', encoding: 'UTF-8'))
print_data = PaoReportsWeb::PrintData.new
  .set_definition(definition).page_start
  .set_value('Title', 'あっという間に帳票出力')
  .set_value('CustomerName', '株式会社パオ').page_end.to_json

server = WEBrick::HTTPServer.new(Port: 8080, BindAddress: '0.0.0.0', Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN), AccessLog: [])
server.mount_proc('/') { |_req, res| res['Content-Type'] = 'text/html; charset=utf-8'; res.body = File.binread('/app/index.html') }
server.mount_proc('/print-data') { |_req, res| res['Content-Type'] = 'application/json'; res.body = print_data }
server.mount_proc('/pdf') do |req, res|
  # reports_web gem: POST /render/pdf to the Reports.Web engine.
  engine = PaoReportsWeb::ReportsWebEngine.new(url: ENV.fetch('REPORTS_ENGINE_URL', 'http://engine:3107'))
  res['Content-Type'] = 'application/pdf'; res.body = engine.render_pdf(req.body)
end
server.mount('/reports.web', WEBrick::HTTPServlet::FileHandler, '/app/reports.web')
server.mount('/demo/reports.web', WEBrick::HTTPServlet::FileHandler, '/app/reports.web')
trap('TERM') { server.shutdown }; trap('INT') { server.shutdown }; server.start
