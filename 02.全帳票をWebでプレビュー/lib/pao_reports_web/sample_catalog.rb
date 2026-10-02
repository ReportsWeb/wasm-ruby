# frozen_string_literal: true
require 'base64'
require 'json'
require 'pg'
require 'time'
require 'reports_web'

module PaoReportsWeb
  # Builds every sample from its PREPDJ definition and the raw framework rows.
  class SampleCatalog
    SAMPLES = %w[quick-start multiples-of-ten postal estimate invoice products business-card design-showcase].freeze

    def initialize(resources:, database_url:)
      @resources = resources
      @database_url = database_url
    end

    def definition(key)
      raise ArgumentError, "Unknown sample: #{key}" unless SAMPLES.include?(key)
      load_definition(key == 'postal' ? 'postal-1.prepdj' : "#{key}.prepdj")
    end

    def print_data(key)
      raise ArgumentError, "Unknown sample: #{key}" unless SAMPLES.include?(key)
      send(key.tr('-', '_')).to_h
    end

    private

    def load_definition(name)
      value = JSON.parse(File.read(File.join(@resources, 'definitions', name), encoding: 'UTF-8'))
      PrintData.validate_definition!(value)
      raise ArgumentError, 'Original definition must use mm' unless (value['CoordinateUnit'] || 'mm') == 'mm'
      value
    end

    def rows(sample, sheet)
      connection = PG.connect(@database_url)
      result = connection.exec_params('SELECT row_data::text FROM reports_framework_rows WHERE sample_key=$1 AND sheet_no=$2 ORDER BY row_no', [sample, sheet]).map { |row| JSON.parse(row['row_data']) }
      result.sort_by! { |row| [row['大分類コード'].to_f, row['小分類コード'].to_f] } if sample == 'products' && sheet == 3
      result
    ensure
      connection&.close
    end

    def simple(key)
      p = PrintData.new.set_definition(definition(key)).page_start
      p.set_value('Text2', "Webブラウザで作った\n印刷データです。") if key == 'quick-start'
      p.page_end
    end
    def quick_start = simple('quick-start')
    def business_card = simple('business-card')
    def design_showcase = simple('design-showcase')

    def multiples_of_ten
      p = PrintData.new.set_definition(definition('multiples-of-ten'))
      1.upto(4) do |page|
        p.page_start.set_value('日付', now).set_value('頁数', "Page - #{page}").set_value('フォントサイズ', "フォントサイズ\n 変更後").change_attributes('フォントサイズ', {'fontSize' => 12})
        # 2ページ目だけ、ページ上部の線「Line3」を非表示にする。空文字と drawing=false を指定する。
        p.set_value('Line3', '', 0, false) if page == 2
        15.times do |line|
          value = (page - 1) * 15 + line + 1
          p.set_value('行番号', value, line).set_value('10倍数', value * 10, line).set_value('横線', '', line)
          # 100で割り切れる値だけ、この行の文字色を青にする。
          p.change_attributes('10倍数', {'foreground' => '#FF0000FF'}, line) if (value * 10) % 100 == 0
        end
        p.page_end
      end
      p
    end

    def postal
      first = load_definition('postal-1.prepdj'); second = load_definition('postal-2.prepdj')
      p = PrintData.new.set_definition(first)
      rows('postal', 1).each_slice(32).with_index do |chunk, page|
        p.page_start(page < 5 ? first : second).set_value('ページ', "Page-#{page + 1}").set_value('日時', now)
        chunk.each_with_index do |row, i|
          p.set_value('郵便番号', row['郵便番号'], i).set_value('市区町村', row['市区町村'], i).set_value('住所', row['住所'], i).set_value('横罫線', '', i)
          p.set_value('網掛け', '', i) if page >= 5 && i.odd?
        end
        row = chunk.first
        p.set_value('QR', "#{row['郵便番号']} #{row['市区町村']}#{row['住所']}".strip) if page < 5
        p.page_end
      end
      p
    end

    def estimate
      cover = load_definition('estimate-cover.prepdj'); body = load_definition('estimate.prepdj')
      details = rows('estimate', 2); p = PrintData.new.set_definition(cover)
      rows('estimate', 1).each do |h|
        p.page_start(cover).set_value('お客様名', h['お客様名']).set_value('担当者名', h['担当者名']).page_end
        p.page_start(body).set_value('見積番号', h['見積番号']).set_value('お客様名', h['お客様名']).set_value('担当者名', h['担当者名']).set_value('見積日', japanese_date(h['見積日'])).set_value('ヘッダ合計', "\\ #{number(h['合計金額'])}").set_value('消費税額', number(h['消費税額'])).set_value('フッタ合計', number(h['合計金額']))
        7.times { |i| %w[品番白 品名白 数量白 単価白 金額白 品番青 品名青 数量青 単価青 金額青].each { |name| p.set_value(name, '', i) } }
        details.select { |r| r['見積番号'].to_s == h['見積番号'].to_s }.each_with_index do |r, i|
          p.set_value('品番', r['品番'], i).set_value('品名', r['品名'], i).set_value('数量', r['数量'], i).set_value('単価', number(r['単価']), i).set_value('金額', number(r['金額']), i)
        end
        p.page_end
      end
      p
    end

    def invoice
      d = definition('invoice'); details = rows('invoice', 2); p = PrintData.new.set_definition(d); px = 96.0 / 25.4
      rows('invoice', 1).each do |h|
        current = details.select { |r| r['請求番号'].to_s == h['請求番号'].to_s }
        customer = h['お客様名'] # 試すときは右辺を 'サンプル商事' に変更できます。
        max_h = [4, repeat(object(d, 'hLine')) - 1].max; max_v = [1, repeat(object(d, 'vLine')) - 1].max
        p.page_start.set_value('txtNo', h['請求番号']).set_value('txtCustomer', customer).set_value('txtDate', now(true)).set_value('Image1', image_data('kakuin.png'))
        adjust = [-5.0, 44.0, -20.0, -10.0, -9.0]; column_x = []; next_x = 0.0
        max_v.times do |j|
          base = object(d, "field#{j + 1}"); x = j.zero? ? base['X'].to_f * px : next_x; column_x << x; next_x = x + (base['Width'].to_f + adjust[j]) * px
        end
        max_h.times do |i|
          p.set_value('hLine', '', i).set_value('LineRect', '', i)
          p.change_attributes('hLine', {'borderWidth' => 0.5 * px}, i) if i.zero?
          p.change_attributes('hLine', {'strokeStyle' => 'Double'}, i) if i == 1
          color = i.zero? ? '#FFFFDAB9' : (i < max_h - 3 ? (i.odd? ? '#FFFFFFFF' : '#FF87CEFA') : '#FFFFFFB4')
          p.change_attributes('LineRect', {'background'=>color,'fillEnabled'=>true,'fillStyle'=>'Solid','borderColor'=>'#FFFFFFFF'}, i)
          max_v.times do |j|
            next if j < 3 && i > current.length
            base = object(d, "field#{j + 1}")
            p.set_value("field#{j + 1}", '', i).change_attributes("field#{j + 1}", {'x'=>column_x[j],'width'=>(base['Width'].to_f+adjust[j])*px,'bold'=>i.zero?,'fontSize'=>i.zero? ? base['FontSizePt'].to_f : 12.0,'horizontalAlignment'=>i.zero? ? 'Center' : (j==1 ? 'Left' : (j.zero? ? 'Center' : 'Right'))}, i)
          end
        end
        0.upto(max_v) { |j| p.set_value('vLine','',j).change_attributes('vLine',{'x'=>j<max_v ? column_x[j] : next_x},j); p.change_attributes('vLine',{'borderWidth'=>0.5*px},j) if j.zero? || j==max_v }
        %w[品番 品名 数量 単価 金額].each_with_index { |label,j| p.set_value("field#{j+1}",label,0) }
        total = 0
        current.each_with_index do |r, row|
          amount = r['数量'].to_i * r['単価'].to_i; total += amount; i=row+1
          p.set_value('field1',r['品番'],i).set_value('field2',r['品名'],i).set_value('field3',r['数量'],i).set_value('field4',number(r['単価']),i).set_value('field5',number(amount),i)
        end
        tax=(total*0.05).round
        [['小計',total],['消費税',tax],['合計',total+tax]].each_with_index { |(label,amount),k| row=max_h-3+k; p.set_value('field4',label,row).set_value('field5',number(amount),row).change_attributes('field4',{'fontSize'=>16,'bold'=>true,'horizontalAlignment'=>'Center'},row) }
        p.set_value('txtTotal',number(total+tax)).change_attributes('hLine',{'strokeStyle'=>'Double'},max_h-3).set_value('hLine','',max_h).change_attributes('hLine',{'borderWidth'=>0.5*px},max_h).page_end
      end
      p
    end

    def products
      big=rows('products',1).to_h{|r|[r['大分類コード'].to_s,r['大分類名称'].to_s]}; small=rows('products',2).to_h{|r|[[r['大分類コード'],r['小分類コード']].join(':'),r['小分類名称'].to_s]}
      stream=[]; prev_big=prev_small=nil; big_count=small_count=0
      rows('products',3).each do |r|
        bn=big[r['大分類コード'].to_s].to_s; sn=small[[r['大分類コード'],r['小分類コード']].join(':')].to_s
        if prev_small && prev_small!=sn then stream << subtotal('small',prev_small,small_count); small_count=0 end
        if prev_big && prev_big!=bn then stream << subtotal('big',prev_big,big_count); big_count=0 end
        stream << {'大分類'=>prev_big==bn ? '' : bn,'小分類'=>prev_small==sn ? '' : sn,'品番'=>r['品番'].to_s,'品名'=>r['品名'].to_s,'kind'=>'detail'}
        prev_big=bn;prev_small=sn;big_count+=1;small_count+=1
      end
      stream << subtotal('small',prev_small,small_count) if prev_small; stream << subtotal('big',prev_big,big_count) if prev_big
      p=PrintData.new.set_definition(definition('products'))
      stream.each_slice(20) do |chunk|
        p.page_start
        chunk.each_with_index do |r,i|
          %w[大分類 小分類 品番 品名].each{|n|p.set_value(n,r[n],i)}
          %w[枠_大分類 枠_小分類 枠_品番 枠_品名].each{|n|p.set_value(n,'',i);p.change_attributes(n,{'background'=>r['kind']=='small' ? '#FFFFFFE0':'#FFFFB6C1','fillEnabled'=>true,'fillStyle'=>'Solid'},i) unless r['kind']=='detail'}
        end
        p.page_end
      end
      p
    end

    def object(d,name) = d.fetch('Objects').find{|o|o['Name']==name} || raise("Missing report object: #{name}")
    def repeat(o) = (o['Repeat'] || o['RepeatCount'] || 0).to_i
    def number(value) = value.to_f.round.to_s.reverse.scan(/.{1,3}/).join(',').reverse
    def japanese_date(value) = value.to_s[0,10].split('-').then{|p|p.length==3 ? "#{p[0]}年#{p[1].to_i}月#{p[2].to_i}日" : value.to_s}
    def now(japanese=false) = japanese ? Time.now.getlocal('+09:00').strftime('%Y年%-m月%-d日') : Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M:%S')
    def image_data(name) = "data:image/png;base64,#{Base64.strict_encode64(File.binread(File.join(@resources,'images',name)))}"
    def subtotal(kind,name,count) = {'大分類'=>'','小分類'=>"#{kind=='small' ? '小分類':'大分類'}(#{name})小計",'品番'=>"#{count} 冊",'品名'=>'','kind'=>kind}
  end
end
