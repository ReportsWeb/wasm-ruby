# frozen_string_literal: true
module PaoReportsWeb
  # B18: an image embedded in a definition belongs in ImageDataBase64. A data: URI in
  # ImagePath made the Pure Java SDK refuse the whole PREPEJ and WPF throw PathTooLongException.
  module ImageEmbedding
    DATA_URI = %r{\Adata:image/[^,;]*;base64,(.*)\z}m
    module_function

    def embed!(object)
      return object unless object.is_a?(Hash) && object['ImagePath'].is_a?(String)
      match = DATA_URI.match(object['ImagePath'])
      object.merge!('ImagePath' => '', 'ImageDataBase64' => match[1]) if match
      object
    end
  end
end