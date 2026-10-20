# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../lib/pao_reports_web/image_embedding'
class ImageEmbeddingTest < Minitest::Test
  def test_data_uri_image_path_moves_to_image_data_base64
    o = {'Name'=>'Image1', 'ImagePath'=>'data:image/png;base64,AQID', 'ImageDataBase64'=>''}
    PaoReportsWeb::ImageEmbedding.embed!(o)
    assert_equal ['', 'AQID'], [o['ImagePath'], o['ImageDataBase64']]
  end
  def test_file_path_and_values_stay
    o = {'Name'=>'Image1', 'ImagePath'=>'kakuin.png'}
    assert_equal 'kakuin.png', PaoReportsWeb::ImageEmbedding.embed!(o)['ImagePath']
    v = {'Name'=>'Image1', 'Value'=>'data:image/png;base64,AQID'}
    assert_equal 'data:image/png;base64,AQID', PaoReportsWeb::ImageEmbedding.embed!(v)['Value']
  end
end