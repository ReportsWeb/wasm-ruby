# frozen_string_literal: true
require 'minitest/autorun'
require 'reports_web'
class PrintDataTest < Minitest::Test
  def definition = {'Version'=>'1','CoordinateUnit'=>'mm','Objects'=>[]}
  def test_values_and_attributes
    d=PaoReportsWeb::PrintData.new.set_definition(definition).page_start.set_value(' total ',12.5).change_attributes('total',{'bold'=>true}).page_end.to_h
    assert_equal 'total', d['Pages'][0]['Values'][0]['Name']; assert_equal '12.5', d['Pages'][0]['Values'][0]['Value']
  end
  def test_invalid_lifecycle
    assert_raises(ArgumentError){PaoReportsWeb::PrintData.new.page_start}
    p=PaoReportsWeb::PrintData.new.set_definition(definition).page_start
    assert_raises(ArgumentError){p.set_value('x',{'bad'=>1})}; assert_raises(ArgumentError){p.to_h}
  end
  def test_indices_and_snapshot
    p=PaoReportsWeb::PrintData.new.set_definition(definition).page_start
    assert_raises(ArgumentError){p.set_value('x','bad',-1)}
    assert_raises(ArgumentError){p.set_value('x','bad',1.5)}
    assert_raises(ArgumentError){p.set_repeated_value('x','bad',0,-1)}
    assert_raises(ArgumentError){p.change_repeated_attributes('x',{},0,x:0)}
    assert_raises(ArgumentError){p.change_repeated_attributes('x',{},0,y:0)}
    text=+'original'
    p.set_value('x',text).page_end
    text.replace('changed')
    snapshot=p.to_h
    snapshot['Definition']['Version']='changed'
    snapshot['Pages'][0]['Values'][0]['Value']='changed'
    assert_equal '1',p.to_h['Definition']['Version']
    assert_equal 1,p.to_h['Pages'][0]['Values'].length
    assert_equal 'original',p.to_h['Pages'][0]['Values'][0]['Value']
  end
end
