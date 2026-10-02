# frozen_string_literal: true
require 'base64'
require 'json'
require 'net/http'
require 'pg'
require 'sinatra/base'
require 'time'
require 'reports_web'
require_relative 'lib/pao_reports_web/sample_catalog'

class ReportsRubyApp < Sinatra::Base
  BASE = '/demo/reports.web/samples/ruby'
  SAMPLES = {'quick-start'=>'あっという間に帳票出力','multiples-of-ten'=>'10のサンプル','postal'=>'郵便番号一覧（定義切替）','estimate'=>'見積書（表紙＋明細）','invoice'=>'請求書','products'=>'商品大小分類（途中で小計）','business-card'=>'名刺','design-showcase'=>'デザイン機能見本'}.freeze
  MAX = 32 * 1024 * 1024
  set :bind, ENV.fetch('HOST','127.0.0.1'); set :port, ENV.fetch('PORT','8096').to_i
  set :server, :puma; set :show_exceptions, false; set :raise_errors, true

  configure do
    set :resources, ENV.fetch('REPORTS_RESOURCE_ROOT','/opt/reports/resources')
    set :fixtures, ENV.fetch('REPORTS_FIXTURE_ROOT','/opt/reports/fixtures')
    set :database_url, ENV['REPORTS_DB_URL']
    set :web_root, ENV.fetch('REPORTS_WEB_ROOT','/opt/reports/web')
    set :template, File.read(ENV.fetch('REPORTS_TEMPLATE','public/index.html'),encoding:'UTF-8')
    set :engine, ENV.fetch('REPORTS_ENGINE_URL','http://127.0.0.1:3107').delete_suffix('/')
    set :asset_base, ENV.fetch('REPORTS_PUBLIC_ASSET_BASE','http://127.0.0.1:8096'+BASE+'/api?action=asset&name=')
    set :preview, ENV.fetch('REPORTS_PREVIEW_URL','/demo/reports.web/preview/')
    set :designer, ENV.fetch('REPORTS_DESIGNER_URL','/demo/reports.web/design/')
    set :render_lock, Mutex.new
  end

  before { headers 'X-Content-Type-Options'=>'nosniff','Cache-Control'=>'no-store' }
  get('/health'){json({'status'=>'UP'})}
  get('/'){redirect BASE+'/',307}
  get(BASE){index_page}; get(BASE+'/'){index_page}
  get(BASE+'/health'){json({'status'=>'UP'})}
  get(BASE+'/api'){api}; get(BASE+'/api.php'){api}; post(BASE+'/api'){api}; post(BASE+'/api.php'){api}

  %w[preview design assets barcode server].each do |directory|
    get "/demo/reports.web/#{directory}/*" do |path|
      path = 'index.html' if path.to_s.empty?
      safe = File.expand_path(path, File.join(settings.web_root,directory)); root=File.expand_path(File.join(settings.web_root,directory))+File::SEPARATOR
      halt 400 unless safe.start_with?(root); send_file safe
    end
  end

  %w[font-map.json fontmap.json preview-help.html].each do |file|
    get "/demo/reports.web/#{file}" do
      send_file File.join(settings.web_root, file)
    end
  end

  error do
    status 500; json({'error'=>env['sinatra.error'].message})
  end

  helpers do
    def json(value,type='application/json',file=nil)
      content_type type; attachment(file) if file; JSON.generate(value)+"\n"
    end
    def sample!
      key=params.fetch('sample','invoice'); halt_json(400,'帳票を選択してください。') unless SAMPLES.key?(key); key
    end
    def halt_json(code,message); halt code,{'Content-Type'=>'application/json'},JSON.generate({'error'=>message}) end
    def read_json(path); JSON.parse(File.read(path,encoding:'UTF-8')) end
    def index_page
      selected=SAMPLES.key?(params['sample']) ? params['sample'] : 'invoice'
      options=SAMPLES.map{|key,label|%(<option value="#{key}"#{' selected' if key==selected}>#{Rack::Utils.escape_html(label)}</option>)}.join
      settings.template.sub('{{SAMPLES}}',options).sub('{{PREVIEW_URL}}',Rack::Utils.escape_html(settings.preview)).sub('{{DESIGNER_URL_JSON}}',JSON.generate(settings.designer))
    end
    def api
      action=params.fetch('action','data'); return asset if action=='asset'; key=sample!
      case action
      when 'catalog' then json(SAMPLES)
      when 'definition'
        name=key=='postal' ? 'postal-1.prepdj' : "#{key}.prepdj"; value=read_json(File.join(settings.resources,'definitions',name));externalize(value,key);inline_assets(value);json(value,'application/vnd.pao.reports-definition+json',"#{key}.prepdj")
      when 'data'
        value=print_data(key);refresh(value,key);inline_assets(value);json(value,'application/vnd.pao.reports-printdata+json',"#{key}.prepej")
      when 'server-pdf' then server_pdf(key)
      else halt_json(400,'未対応の操作です。')
      end
    end
    def print_data(key)
      raise 'REPORTS_DB_URL is required' unless settings.database_url
      PaoReportsWeb::SampleCatalog.new(resources: settings.resources, database_url: settings.database_url).print_data(key)
    end
    def asset
      name=params.fetch('name','');halt_json(400,'未登録の画像資源です。') unless %w[kakuin.png estimate-header.jpg].include?(name);path=File.join(settings.resources,'images',name);content_type(name.end_with?('.jpg') ? 'image/jpeg':'image/png');File.binread(path)
    end
    def each_value(value,&block)
      case value;when Hash then value.to_a.each{|k,v|yield(value,k,v);each_value(value[k],&block)};when Array then value.each{|v|each_value(v,&block)};end
    end
    def externalize(value,key)
      return unless value.is_a?(Hash)
      Array(value['Objects']).each{|o|n=o['Name'];file=((%w[invoice estimate].include?(key)&&n=='Image1') ? 'kakuin.png' : (key=='estimate'&&n=='Image2' ? 'estimate-header.jpg':nil));o.merge!('ImagePath'=>settings.asset_base+file,'ImageDataBase64'=>'') if file}
    end
    def refresh(value,key)
      externalize(value['Definition'],key);today=Time.now.getlocal('+09:00');each_value(value){|parent,name,_|next unless name=='Value';parent[name]="#{today.year}年#{today.month}月#{today.day}日" if parent['Name']=='txtDate';parent[name]=settings.asset_base+'kakuin.png' if key=='invoice'&&parent['Name']=='Image1'};Array(value['Pages']).each{|page|externalize(page['Definition'],key)}
    end
    def inline_assets(value)
      each_value(value){|parent,key,item|next unless item.is_a?(String);if item.start_with?(settings.asset_base);name=item.delete_prefix(settings.asset_base);halt_json(400,'未登録の画像資源です。') unless %w[kakuin.png estimate-header.jpg].include?(name);type=name.end_with?('.jpg')?'image/jpeg':'image/png';parent[key]="data:#{type};base64,#{Base64.strict_encode64(File.binread(File.join(settings.resources,'images',name)))}";elsif key=='ImagePath'&&!item.empty?&&!item.start_with?('data:');halt_json(400,'外部画像は登録した画像か埋め込み画像を使用してください。');end}
    end
    def server_pdf(key)
      halt_json(405,'POSTを使用してください。') unless request.post?;halt_json(429,'PDF作成中です。少し待ってからお試しください。') unless settings.render_lock.try_lock
      begin
        body=request.body.read(MAX+1);halt_json(413,'印刷データが大きすぎます。') if body.bytesize>MAX;value=JSON.parse(body);inline_assets(value);begin;pdf=PaoReportsWeb::ReportsWebEngine.new(url:settings.engine).render_pdf(value);rescue PaoReportsWeb::ReportsWebEngineError;halt_json(502,'サーバーでPDFを作成できませんでした。');end;content_type 'application/pdf';headers 'Content-Disposition'=>%(inline; filename="#{key}.pdf"),'X-Reports-Engine'=>'server-wasm';pdf
      rescue JSON::ParserError;halt_json(400,'JSON形式が不正です。')
      ensure settings.render_lock.unlock if settings.render_lock.owned?
      end
    end
  end
end

ReportsRubyApp.run! if $PROGRAM_NAME == __FILE__
