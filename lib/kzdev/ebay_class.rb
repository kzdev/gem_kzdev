require 'ebayr'

class EbayClass
  # ebaytokenを設定
  # @param [String] ebay_key
  # @return [nil]
  def set_auth_token(ebay_key)
    Ebayr.auth_token = ebay_key
  end

  # 出品中商品を取得
  # @return [Hash]
  def get_my_ebay_selling
    data = Ebayr.call(:GetMyeBaySelling, :SoldList => {:ActiveList=>{:Sort => "TimeLeft"}})
    check_result(data) ? data : nil
  end

  # 商品IDから商品情報を取得
  # @param [String] item_id
  # @return [Hash]
  def get_item(item_id)
    data = Ebayr.call(:GetItem, :ItemID => item_id)
    check_result(data) ? data : nil
  end

  # カテゴリ情報を取得
  # @param [Int] category_side_id
  # @param [Int] level_limit
  # @return [Array]
  def get_category(category_side_id=0, level_limit=1)
    Ebayr.call(:GetCategories ,
               :CategorySiteID => category_side_id,
               :DetailLevel => 'ReturnAll',
               :LevelLimit => level_limit).category_array.category
  end

  # 発送可能地域を取得
  # @return [Hash]
  def get_location
    Ebayr.call(:GeteBayDetails).shipping_location_details
  end

  # 出品商品情報を更新
  # @param [Hash] 商品情報
  # @return [Boolean]
  def revise_item(data, error)
    error = ""
    data = Ebayr.call(:ReviseItem ,:Item => data);
    if  data.ack == "Failure"
      error = data.errors.to_s
      false
    elsif data.ack == "Warning"
      error = data.errors.to_s
      true
    else
      true
    end
  end

  # 出品商品情報を新規出品
  # @param [Hash] 商品情報
  # @return [Boolean]
  def add_item(data, error)
    error = ""
    data = Ebayr.call(:AddItem ,:Item => data);
    if  data.ack == "Failure"
      error = data.errors.to_s
      false
    elsif data.ack == "Warning"
      error = data.errors.to_s
      true
    else
      true
    end
  end

  # 指定した商品の出品を取り消す
  # @param [String] item_id
  # @param [String] error
  # @return [Boolean]
  def end_item(item_id, error)
    error = ""
    data = Ebayr.call(:EndItem, :ItemID => item_id, :EndingReason => 'NotAvailable')
    if  data.ack == "Failure"
      error = data.errors.to_s
      false
    elsif data.ack == "Warning"
      error = data.errors.to_s
      true
    else
      true
    end
  end

  # 指定した商品を再出品する
  # @param [String] item_id
  # @param [String] error
  # @return [Boolean]
  def relist_item(item_id, error)
    error = ""
    data = Ebayr.call(:RelistItem, :Item=>{:ItemID => item_id})
    if  data.ack == "Failure"
      error = data.errors.to_s
      false
    elsif data.ack == "Warning"
      error = data.errors.to_s
      true
    else
      true
    end
  end

  # カテゴリ毎の項目情報を取得する
  # @param [String] category_id
  # @return [Hash]
  def category_features(category_id)
    Ebayr.call(:GetCategorySpecifics,
               :CategorySpecific => {:CategoryID => category_id})
  end


private
  # コンストラクタ
  # @param [String] dev_id
  # @param [String] app_id
  # @param [String] cert_id
  # @param [Boolean] sandbox
  # @return [nil]
  def initialize(dev_id, app_id, cert_id, sandbox)
    Ebayr.dev_id  = dev_id
    Ebayr.app_id  = app_id
    Ebayr.cert_id = cert_id
    Ebayr.sandbox = sandbox
  end

  def check_result(data)
    if data.ack == "Failure"
      false
    else
      true
    end
  end
end
