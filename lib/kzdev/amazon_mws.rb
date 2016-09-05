require 'peddler'

class AmazonMwsClass
  # コンストラクタ
  # @param [String] marketplace_id
  # @param [String] merchant_id
  # @param [String] aws_access_key_id
  # @param [String] aws_secret_access_key
  def initialize(marketplace_id, merchant_id, aws_access_key_id, aws_secret_access_key)
    @@redis = REDIS

    opt = {
      marketplace_id:        marketplace_id,
      merchant_id:           merchant_id,
      aws_access_key_id:     aws_access_key_id,
      aws_secret_access_key: aws_secret_access_key
    }

    # 注文
    @@orders   = MWS.orders(opt)
    # レポート
    @@reports  = MWS.reports(opt)
    # 出品
    @@feeds    = MWS.feeds(opt)
    # 商品情報
    @@products = MWS.products(opt)
    # レコメンド
    @@recommend = MWS.recommendations(opt)

    @@country = get_country(marketplace_id)
  end

  def get_service_status
    result = {}
    result[:order]     = @@orders.get_service_status.parse["Status"]
    result[:product]   = @@products.get_service_status.parse["Status"]
    result[:recommend] = @@recommend.get_service_status.parse["Status"]

    # APIステータスが異常の場合は処理停止
    @@orders = nil if result[:order] == "RED"
    @@products = nil if result[:products] == "RED"
    @@recommend = nil if result[:recommend] == "RED"

    result
  end

  def check_status(obj)
    raise "API status error." if obj.nil?
  end





  # -----------------------------------------------------------
  #                         ORDER API
  # -----------------------------------------------------------
  def list_order
    check_status(@@orders)

    begin
      response = @@orders.list_orders(created_after: 1.month.ago)
      response.parse
    rescue => ex
      pp "method:"+__method__+" error:"+ex.message
      return nil
    end
  end

  # 注文番号から商品情報を取得
  # @param amazon_order_id 注文番号
  def list_order_items(amazon_order_id)
    check_status(@@orders)

    begin
      response = @@orders.list_order_items(amazon_order_id)
      response.parse
    rescue => ex
      pp "method:"+__method__+" amazon_order_id:"+amazon_order_id.to_s+" error:"+ex.message
      return nil
    end
  end






  # -----------------------------------------------------------
  #                       REPORT API
  # -----------------------------------------------------------


  # レポートIDリストを取得
  # 最終更新日より新しいレポートの場合、:newをtrueに設定
  #
  # redis AMAZON_REPORT_PREFIX user_id last_update
  # @param type 列挙型から指定 http://docs.developer.amazonservices.com/ja_JP/reports/Reports_ReportType.html
  def get_report_list(user_id=nil, type=nil)
    check_status(@@reports)

    result = {}

    begin
      response = @@reports.get_report_list({:report_type_list => type})
      node = response.parse
    rescue => ex
      pp "method:"+__method__+" error:"+ex.message
      return nil
    end

    while true
      break if !node.key?("ReportInfo")

      # redisから指定ユーザの最終更新日を取得
      _new_last_update = nil
      last_recieve_time = user_id.nil? ? nil : @@redis.hget(AMAZON_REPORT_PREFIX, user_id)

      # レポートリストを取得
      node["ReportInfo"].each do |report|
        result[report["ReportId"]] = {:type => report["ReportType"], :date => report["AvailableDate"], :new => false}
        _recieve_time = DateTime.parse(report["AvailableDate"])

        # 最終更新日よりも更新日が新しい場合は戻り値に含める
        if last_recieve_time.nil? || DateTime.parse(last_recieve_time) < _recieve_time
          result[report["ReportId"]][:new] = true
          _new_last_update = _recieve_time if _new_last_update.nil? || _new_last_update < _recieve_time
        end
      end

      @@redis.hset(AMAZON_REPORT_PREFIX+@@country, user_id, _new_last_update) if user_id && !_new_last_update.nil?

      break if node["HasNext"] != "true"

      begin
        response = @@reports.get_report_list_by_next_token(node["NextToken"])
        node = response.parse
      rescue => ex
        pp "method:"+__method__+" error:"+ex.message
        return nil
      end
    end

    result
  end


  # レポートを取得
  # @param report_id レポートID
  def get_report(report_id)
    begin
      response = @@reports.get_report(report_id)
      node = response.parse
      ret = nil

      if node.instance_of?(CSV::Table)
        case @@country
        when "jp"
          csv = ""
          node.each do |row|
            csv << row.to_s.force_encoding("utf-8").chomp.gsub("\"<", "<").gsub(">\"", ">").gsub("\"\"", "\"")
          end
          node = Nokogiri.parse(csv)
          ret = parse_report_csv(node)
        when "us"
          csv = []
          node.each do |row|
            csv << row.to_hash
          end
          ret = csv
        when "ca"
          csv = []
          node.each do |row|
            csv << row.to_hash
          end
          ret = csv
        when "uk"
          #TODO
        end
      else
        ret = node
      end
    rescue => ex
      pp "error:"+ex.message
      return nil
    end
    ret

  end






  # -----------------------------------------------------------
  #                       FEED API
  # -----------------------------------------------------------

  # 1. submit_feed(商品出品 -> 在庫 -> 価格 -> 画像 -> 送料)
  # 2. 1.で帰ってきたFeedSubmissionIdを元にステータスを監視
  # 3. 2.でDONEになれば出品完了

  # 出品
  # @params [Hash] data
  def listing_post(data)
    type = "_POST_FLAT_FILE_INVLOADER_DATA_"
    _temp = Tempfile.new("listing_data_")
    filename = _temp.path

    begin
      header = ""
      header_tmp = []
      data[0].each do |k ,v|
        header << "#{k}\t"
        header_tmp << k
      end
      #header << "sku\t"
      #header << "product-id\t"
      #header << "product-id-type\t"
      #header << "item-condition\t"
      #header << "price\t"
      #header << "quantity\t"
      #header << "item_note\t"
      #header << "will-ship-internationally\t"
      #header << "expedited-shipping\t"
      #header << "add-delete\t"
      #header << "minimum-seller-allowed-price\t"
      #header << "maximum-seller-allowed-price\t"
      #header << "fulfillment-center-id\t"
      #header << "leadtime-to-ship\t"
      #header << "product-tax-code"
      _temp.puts header

      data.each do |row|
        _row_str = parse_listing_post_date(header_tmp, row)
        _temp.puts _row_str unless _row_str.blank?
      end
    ensure
      _temp.close
    end
    pp "[POST]amazon_mws listing_post middle file. #{_temp.path}"

    begin
      ret = {}
      ret[:data] = submit_feed(open(_temp).read, type)
      #ret[:data] = ""
      ret[:filepath] = filename
    rescue => ex
      pp "method:"+__method__+" error:"+ex.message
      return nil
    end
    ret
  end

  # フィードを発行(2G以上はNG)
  # @param type xsd 送信するcontent
  # @param type feed_type フィードタイプ
  def submit_feed(xsd, feed_type)
    raise "Error XML size over." if xsd.bytesize > 2147483646
    response = @@feeds.submit_feed(xsd, feed_type)

    response.parse
  end


  # フィード処理リストを取得
  # @param type 列挙型から指定 http://docs.developer.amazonservices.com/ja_JP/feeds/Feeds_FeedType.html
  def get_feed_submission_list(type=nil)
    result = {}
    begin
      response = @@feeds.get_feed_submission_list({:feed_type_list => type})
      node = response.parse
    rescue => ex
      pp "error:"+ex.message
      return nil
    end

    while true
      break if !node.key?("FeedSubmissionInfo")

      node["FeedSubmissionInfo"].each do |submission|
        result[submission["FeedSubmissionId"]] = {
          :type => submission["FeedType"],
          :start_data => submission["SubmittedDate"],
          :end_date => submission["CompletedProcessingDate"],
          :status => submission["FeedProcessingStatus"]
        }
      end

      break if node["HasNext"] != "true"

      begin
        response = @@feeds.get_feed_submission_list_by_next_token(node["NextToken"])
        node = response.parse
      rescue => ex
        pp "method:"+__method__+" error:"+ex.message
        return nil
      end
    end

    result
  end

  # フィード処理結果を取得
  # @param feed_submission_id フィード処理ID
  def get_feed_submission_result(feed_submission_id)
    begin
      response = @@feeds.get_feed_submission_result(feed_submission_id)

      if response.respond_to?("body")
        result = response.body
      else
        node = response.parse
        result = []
        node.each do |row|
          result << row.to_hash
        end
      end
    rescue => ex
      pp "method:"+__method__+" feed_submission_id:"+feed_submission_id+" error:"+ex.message
      return nil
    end

    result
  end


  # -----------------------------------------------------------
  #                       PRODUCT API
  # -----------------------------------------------------------

  # SKUから出品されているかどうかを確認する
  # @param sku 該当する商品ASIN
  def get_my_price_for_sku(sku)
    check_status(@@products)

    ret = {}
    begin
      response = @@products.get_my_price_for_sku(sku)
      node = response.parse
      ret[:asin] = node["Product"]["Identifiers"]["MarketplaceASIN"]["ASIN"]
      ret[:price] = node["Product"]["Offers"]["Offer"]["BuyingPrice"]["ListingPrice"]["Amount"]
      ret[:shipping] = node["Product"]["Offers"]["Offer"]["BuyingPrice"]["Shipping"]["Amount"]
    rescue
      if ret.key?(:asin)
        return ret
      else
        return nil
      end
    end
    ret
  end

  # 同一商品を出品している競合他社の価格情報を取得
  # 主に出品数とランキングをブラウズノード毎に調べる
  # @param asin 調べたい商品のASIN
  def get_competitive_pricing_for_asin(asin)
    check_status(@@products)

    result = {}
    retry_cnt = 0

    begin
      response = @@products.get_competitive_pricing_for_asin(asin)
      node = response.parse
    rescue => ex
      if RETRY_COUNT<retry_cnt
        pp "get_competitive_pricing_for_asin error. retry_cnt=#{retry_cnt}"
        retry_cnt += 1
        retry
      end
      pp "asin:"+asin.to_s+" error:"+ex.message
      return nil
    end

    return nil if node.blank?

    # price
    begin
      if node["Product"]["CompetitivePricing"]["CompetitivePrices"]["CompetitivePrice"].instance_of?(Array)
        node["Product"]["CompetitivePricing"]["CompetitivePrices"]["CompetitivePrice"].each do |price|
          if price["condition"] == "New"
            result[:price] = price["Price"]["ListingPrice"]["Amount"]
            result[:shipping] = price["Price"]["Shipping"]["Amount"]
            result[:currency] = price["Price"]["Shipping"]["CurrencyCode"]
            break
          end
        end
      else
        _node = node["Product"]["CompetitivePricing"]["CompetitivePrices"]["CompetitivePrice"]["Price"]
        _condition = node["Product"]["CompetitivePricing"]["CompetitivePrices"]["CompetitivePrice"]["condition"]
        if _condition == "New"
          result[:price] = _node["ListingPrice"]["Amount"]
          result[:shipping] = _node["Shipping"]["Amount"]
          result[:currency] = _node["Shipping"]["CurrencyCode"]
        end
      end
    rescue => ex
      #pp "price elemet not found."
      return
    end

    # offer
    begin
      node["Product"]["CompetitivePricing"]["NumberOfOfferListings"]["OfferListingCount"].each do |offer|
        result[:any_count] = offer["__content__"] if offer["condition"] == "Any"
        result[:used_count] = offer["__content__"] if offer["condition"] == "Used"
        result[:new_count] = offer["__content__"] if offer["condition"] == "New"
      end
    rescue => ex
      pp "offer element not found."
      return
    end

    # rank
    # ランキングはTOPカテゴリのみを取得
    begin
      result[:ranks] = []
      node["Product"]["SalesRankings"]["SalesRank"].each do |rank|
        _rank = {}
        # 不要文字列を削除
        _rank[:id] = rank["ProductCategoryId"]
        _rank[:rank] = rank["Rank"]
        result[:ranks] << _rank
        break
      end
    rescue => ex
      #pp "rank element not found."
    end

    result
  end


  # 同一商品を出品している最低価格情報を取得
  # @param asin 調べたい商品のASIN
  def get_lowest_offer_listings_for_asin(asin, condition="new")
    check_status(@@products)
    retry_cnt = 0

    begin
      response = @@products.get_lowest_offer_listings_for_asin(asin, {:item_condition => condition})
      node = response.parse
      return if node.blank? || node["Product"]["LowestOfferListings"].nil?
    rescue => ex
      if RETRY_COUNT<retry_cnt
        pp "get_lowest_offer_listings_for_asin error. retry_cnt=#{retry_cnt}"
        retry_cnt += 1
        retry
      end
      pp "asin:"+asin.to_s+" error:"+ex.message
      return nil
    end

    result = []
    if node["Product"]["LowestOfferListings"]["LowestOfferListing"].instance_of?(Array)
      node["Product"]["LowestOfferListings"]["LowestOfferListing"].each {|price|
        _node = price["Qualifiers"]
        _tmp = {}

        _tmp[:channel] = _node["FulfillmentChannel"] # 出荷元
        _tmp[:shipping_time] = _node["ShippingTime"]["Max"] # 発送日数(最大)
        _tmp[:shipping_domestic] = _node["ShipsDomestically"] # 国内から発送
        _tmp[:seller_positive_rating] = _node["SellerPositiveFeedbackRating"] # 出品者のポジティブ評価率

        _tmp[:seller_feedback_count] = price["SellerFeedbackCount"] # 出品者のフィードバック数
        _tmp[:offer_count] = price["NumberOfOfferListingsConsidered"] # 出品数

        _price = price["Price"]
        _tmp[:currency] = _price["ListingPrice"]["CurrencyCode"]
        _tmp[:price] = _price["ListingPrice"]["Amount"]
        _tmp[:shipping] = _price["Shipping"]["Amount"]

        result << _tmp
      }
    else
      _tmp = {}

      price = node["Product"]["LowestOfferListings"]["LowestOfferListing"]
      _node = node["Product"]["LowestOfferListings"]["LowestOfferListing"]["Qualifiers"]

      _tmp[:channel] = _node["FulfillmentChannel"] # 出荷元
      _tmp[:shipping_time] = _node["ShippingTime"]["Max"] # 発送日数(最大)
      _tmp[:shipping_domestic] = _node["ShipsDomestically"] # 国内から発送
      _tmp[:seller_positive_rating] = _node["SellerPositiveFeedbackRating"] # 出品者のポジティブ評価率

      _tmp[:seller_feedback_count] = price["SellerFeedbackCount"] # 出品者のフィードバック数
      _tmp[:offer_count] = price["NumberOfOfferListingsConsidered"] # 出品数

      _price = node["Product"]["LowestOfferListings"]["LowestOfferListing"]["Price"]
      _tmp[:currency] = _price["ListingPrice"]["CurrencyCode"]
      _tmp[:price] = _price["ListingPrice"]["Amount"]
      _tmp[:shipping] = _price["Shipping"]["Amount"]

      result << _tmp
    end
    result
  end

  # 商品情報を取得
  # @param asin 調べたい商品のASIN
  def get_matching_product(asin)
    check_status(@@products)
    retry_cnt = 0

    begin
      response = @@products.get_matching_product(asin)
      node = response.parse
      return if node.blank? || !node.key?("Product")
    rescue => ex
      if RETRY_COUNT<retry_cnt
        pp "get_matching_product error. retry_cnt=#{retry_cnt}"
        retry_cnt += 1
        retry
      end
      pp "asin:"+asin.to_s+" error:"+ex.message
      return nil
    end

    result = {}
    result[:brand] = node["Product"]["AttributeSets"]["ItemAttributes"]["Brand"]
    result[:model] = node["Product"]["AttributeSets"]["ItemAttributes"]["Model"]
    result[:product_group] = node["Product"]["AttributeSets"]["ItemAttributes"]["ProductGroup"]
    result
  end

  # 指定商品の所属ブラウズノードを取得
  # @param asin 調べたい商品のASIN
  def get_product_categories_for_asin(asin)
    check_status(@@products)
    response = @@products.get_product_categories_for_asin(asin)
    response.parse
  end

private
  # レポート(CSV)をハッシュ形式にパース
  # @param node XML ELEMENT(Nokogiri)
  def parse_report_csv(node)
    type = (node/"AmazonEnvelope/MessageType").text
    return if type.blank?

    _tmp_node = (node/"AmazonEnvelope/Message/#{type}")
    return if _tmp_node.blank?

    result = {}
    case type
    when "OrderReport"
      result["order_id"] = (_tmp_node/"AmazonOrderID").text
      result["order_date"] = (_tmp_node/"OrderDate").text
      result["email"] = (_tmp_node/"BillingData/BuyerEmailAddress").text
      result["name"] = (_tmp_node/"BillingData/BuyerName").text
      result["name"] = (_tmp_node/"FulfillmentData/Address/Name").text
      result["address_1"] = (_tmp_node/"FulfillmentData/Address/AddressFieldOne").text
      result["address_2"] = (_tmp_node/"FulfillmentData/Address/AddressFieldTwo").text
      result["region"] = (_tmp_node/"FulfillmentData/Address/StateOrRegion").text
      result["postal_code"] = (_tmp_node/"FulfillmentData/Address/PostalCode").text
      result["country"] = (_tmp_node/"FulfillmentData/Address/CountryCode").text
      result["item_code"] = (_tmp_node/"Item/AmazonOrderItemCode").text
      result["sku"] = (_tmp_node/"Item/SKU").text
      result["title"] = (_tmp_node/"Item/Title").text
      result["quantity"] = (_tmp_node/"Item/Quantity").text
      (_tmp_node/"Item/ItemPrice/Component").each do |component|
        component_type = (component/"Type").text
        result["#{component_type.downcase}_amount"] = (component/"Amount").first.text
      end
    end
    result
  end


  # 国コードを取得
  # @param marketplace_id マーケットプレイスID
  def get_country(marketplace_id)
    case marketplace_id
    when "A2EUQ1WTGCTBG2"
      "ca"
    when "A1VC38T7YXB528"
      "jp"
    when "ATVPDKIKX0DER"
      "us"
    when "A1PA6795UKMFR9","A1RKKUPIHCS9HS","A13V1IB3VIYZZH","A1F83G8C2ARO7P","APJ6JRA9NG5V4"
      "eu"
    end
  end


  # xml elementから文字列を取得
  # @param [xml] xmlノード
  # @param [String] 表示タイプを指定
  # @return [String] nodeに含まれる文字列
  def check_value(element, type=nil)
    element.respond_to?(:text) ? element.text : nil
  end

  # 出品情報を出品用ファイル出力用に整形する
  # @param [Hash] 出品情報
  # @return [String] 出品用ファイルの１行
  def parse_listing_post_date(header, data)
    result = ""

    header.each do |h|
      result << data[h].to_s + "\t"
    end

    result
  end
end
