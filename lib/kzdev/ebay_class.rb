require 'ebayr'

class EbayClass
  # ebaytoken$B$r@_Dj(B
  # @param [String] ebay_key
  # @return [nil]
  def set_auth_token(ebay_key)
    Ebayr.auth_token = ebay_key
  end

  # $B=PIJCf>&IJ$r<hF@(B
  # @return [Hash]
  def get_my_ebay_selling
    data = Ebayr.call(:GetMyeBaySelling, :SoldList => {:ActiveList=>{:Sort => "TimeLeft"}})
    check_result(data) ? data : nil
  end

  # $B>&IJ(BID$B$+$i>&IJ>pJs$r<hF@(B
  # @param [String] item_id
  # @return [Hash]
  def get_item(item_id)
    data = Ebayr.call(:GetItem, :ItemID => item_id)
    check_result(data) ? data : nil
  end

  # $B%+%F%4%j>pJs$r<hF@(B
  # @param [Int] category_side_id
  # @param [Int] level_limit
  # @return [Array]
  def get_category(category_side_id=0, level_limit=1)
    Ebayr.call(:GetCategories ,
               :CategorySiteID => category_side_id,
               :DetailLevel => 'ReturnAll',
               :LevelLimit => level_limit).category_array.category
  end

  # $BH/Aw2DG=CO0h$r<hF@(B
  # @return [Hash]
  def get_location
    Ebayr.call(:GeteBayDetails).shipping_location_details
  end

  # $B=PIJ>&IJ>pJs$r99?7(B
  # @param [Hash] $B>&IJ>pJs(B
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

  # $B=PIJ>&IJ>pJs$r?75,=PIJ(B
  # @param [Hash] $B>&IJ>pJs(B
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

  # $B;XDj$7$?>&IJ$N=PIJ$r<h$j>C$9(B
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

  # $B;XDj$7$?>&IJ$r:F=PIJ$9$k(B
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

  # $B%+%F%4%jKh$N9`L\>pJs$r<hF@$9$k(B
  # @param [String] category_id
  # @return [Hash]
  def category_features(category_id)
    Ebayr.call(:GetCategorySpecifics,
               :CategorySpecific => {:CategoryID => category_id})
  end


private
  # $B%3%s%9%H%i%/%?(B
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
