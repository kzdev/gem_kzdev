require "redis"
require "amazon/ecs"

class AmazonEcsClass
  attr_accessor :country

  AMAZON_NODE_PREFIX = "amazon_node_"
  AMAZON_ASIN_PREFIX = "amazon_asin"

  private
  # コンストラクタ
  # @param [String] associate_tag
  # @param [String] accesss_key_id
  # @param [String] secret_key
  # @param [String] country
  def initialize(associate_tag, access_key_id, secret_key, country)
    @@redis = Redis.new
    @country = country

    Amazon::Ecs.options = {
      :associate_tag => associate_tag,
      :AWS_access_key_id => access_key_id,
      :AWS_secret_key => secret_key
    }
  end

  public
  # amazonから商品を検索
  # 注意: 送料は取れないのでMWSを利用して取得すること(ランクもところどころ取れていない)
  # @param keyword 検索キーワード
  # @param sort ソート指定
  # @param page 商品取得の上限ページ指定(10ページ以上はamazonの制約で取れない)
  # @param response_group 情報の粒度を指定
  # return [Hash] 取得した商品情報をページ単位で戻す
  def search_item(keyword, sort_element='salesrank', response_group='Offers, OfferFull, ItemAttributes, Images', page=10)
    result = {}
    items = []

    page_no = 1
    total_page = 1

    while true
      break if total_page < page_no
      retry_count = 0

      begin
        #response = Amazon::Ecs.item_search(keyword, {:response_group => response_group, :sort => sort_element,
        #           :condition => 'New', :country => 'jp', :search_index => 'All', :item_page => page_no}).doc
        response = Amazon::Ecs.item_search(keyword, {:search_index => 'All', :response_group => response_group, :condition => 'New', :country => 'jp', :item_page => page_no}).doc

      rescue => e
        pp "retry_count: #{retry_count} message: #{e.message}"

        return nil if e.message.include?("Bad Request")

        retry_count += 1

        if retry_count > 4
          pp "amazon-ecs api failed. threshold over."
          return nil
        end

        sleep 2
        retry
      end

      if page_no ==1
        result[:total_result] = check_value((response/'ItemSearchResponse/Items/TotalResults'))
        total_page = result[:total_page] = check_value((response/'ItemSearchResponse/Items/TotalPages'))
        total_page = total_page.to_i>10 ? 10 : total_page.to_i
      end

      items << _get_item_attributes((response/'ItemSearchResponse/Items/Item'))
      page_no += 1
    end
    result[:data] = items
    result
  end


  # ブラウズノードのASINを取得
  # @param response_group レスポンスグループの指定
  # @param browse_node_id ブラウズノード指定(ない場合は全てのブラウズノードから取得)
  # return [Array] ASINを配列で戻す
  def get_category_asin(response_group, browse_node_id=nil)
    return if @lock && DateTime.parse(@lock) > 1.hour.ago

    counter = 0
    assin = []

    browse_nodes = []
    if browse_node_id
      browse_nodes = browse_node_id
    else
      @@redis.hkeys(AMAZON_NODE_PREFIX+@country).each do |k|
        browse_nodes << k
      end
    end

    browse_nodes.each do |_node_id|
      begin
        last_update = @@redis.hget(AMAZON_ASIN_PREFIX+@country+"_last", _node_id)
        if last_update && DateTime.parse(last_update) > 3.hours.ago
          pp "#{_node_id} skip"
          next
        end

        pp _node_id
        # 1秒～5秒間スリープ
        sleep rand(5) + 1
        response = Amazon::Ecs.browse_node_lookup(_node_id, { :response_group => response_group , :country => @country })

        items = response.doc.search(response_group).each_with_object([])
        items.each do |k, arr|
          pp k.at('ASIN').text
          assin << [k.at('ASIN').text, _node_id]
          @@redis.hset(AMAZON_ASIN_PREFIX+@country, k.at('ASIN').text, Time.now)
        end

        # ブラウズノード毎に最終処理時刻更新
        @@redis.hset(AMAZON_ASIN_PREFIX+@country+"_last", _node_id, Time.now)

      rescue => e
        pp "retry: #{counter} message: #{e.message}"
        counter += 1

        # amazonのアカウント凍結回避のため規定のエラー数を超過したアカウントをロックアウト
        if counter>AMAZON_ERROR
          @lock = Time.now.strftime("%Y%m%d%H%M%S")
          raise "Amazon API over error threshold."
        elsif counter>AMAZON_WARNING
          next
        end

        retry
      end
    end

    assin
  end



  # amazonから商品情報を取得
  # @params [Integer] asin ASINコード
  # @return [Hash] 商品情報を返す
  def get_item_description(asin)
    retry_count = 0
    begin
      response = Amazon::Ecs.item_lookup(asin, {:response_group => 'Large, ItemAttributes, Images',  :country => @country }).items
    rescue => e
      pp "retry_count: #{retry_count} message: #{e.message}"

      return nil if e.message.include?("Bad Request")

      retry_count += 1

      if retry_count > 4
        pp "amazon-ecs api failed. threshold over."
        return nil
      end

      sleep 2
      retry
    end
    _get_item_attributes(response, true)[0]
  end



  # amazonからブラウズノードを取得してREDISに保存
  # argsのbrowse_nodesに指定がない場合は、全てのブラウズノードを取得
  # @params [String] country 国を指定(:us, :jp, :uk, :ca)
  # @params [Array] browse_nodes
  # @return [Hash] browse_nodeを返す
  def save_browsenode(browse_nodes=nil)
    #AmazonBrowseNode.all.delete_all
    @@redis.keys(AMAZON_NODE_PREFIX+"*").each do |key|
      @@redis.del key
    end

    counter = 0

    if browse_nodes
      queue = browse_nodes
    else
      queue = _get_top_browsenode_id
    end

    while queue.size>0
      _pnum = queue.shift
      _nodes = _get_browse_node(_pnum)

      # childnode getting
      _nodes.each do |key, val|
        #data = {browse_node_id: key, parent_node_id: _pnum, name: val}
        @@redis.hmset(AMAZON_NODE_PREFIX+@country, key, val)
        queue.push key
        counter += 1
      end

      pp "request queue size is #{queue.size}"
    end

    counter
  end


  private
  # amazonからブラウズノードを取得（API実行）
  # @params [Integer] node_no 検索するブラウズノードを指定
  # @return [Hash] {browse_node_id => name}
  def _get_browse_node(node_no)
    retry_count = 0
    begin
      nodes = Amazon::Ecs.browse_node_lookup(node_no, { :country => @country })
    rescue => e
      retry_count += 1
      pp "retry_count: #{retry_count} message: #{e.message}"

      if retry_count > 4
        pp "amazon-ecs api failed. threshold over."
        return
      end

      sleep 4
      retry
    end
    node = (nodes.doc/"BrowseNodeLookupResponse"/"BrowseNodes"/"BrowseNode"/"Children"/"BrowseNode").map {|item| Amazon::Element.new(item).get_hash }
    Hash[node.map{|item| [item["BrowseNodeId"], item['Name']]}]
  end


  # AmazonのWebページからブラウズノードトップレベルを取得
  # @return [Array] [browse_node_id]
  def _get_top_browsenode_id()
    top_id = []

    agent = Mechanize.new
    agent.user_agent = 'Windows IE 9'
    agent.get("http://docs.aws.amazon.com/AWSECommerceService/latest/DG/BrowseNodeIDs.html")

    if @country == 'jp' then country_id = 9
    elsif @country == 'us' then country_id = 11
    elsif @country == 'ca' then country_id = 2
    elsif @country == 'uk' then country_id = 10
    else
      return
    end

    52.times do |num|
      _tmp = agent.page.root.search("//*[@id='divContent']/div[1]/div[2]/table/tbody/tr[#{num+1}]/td[#{country_id}]").text
      top_id << _tmp if !_tmp.blank?
    end

    top_id
  end


  # xml elementから文字列を取得
  # @param [xml] xmlノード
  # @param [String] 表示タイプを指定
  # @return [String] nodeに含まれる文字列
  def check_value(element, type=nil)
    if type == :image
      if element.respond_to?(:first)
        element.first.respond_to?(:text) ? element.first.text : nil
      else
        element.respond_to?(:text) ? element.text : nil
      end
    elsif type == :size
      if element.respond_to?(:first)
        element.first.respond_to?(:text) ? element.first.text : nil
      else
        element.respond_to?(:text) ? element.text : nil
      end
    elsif type == :weight
      _tmp = element.respond_to?(:text) ? element.text : nil
      # convert pond to g
      ((_tmp.to_i / (100 * 0.454)).round(1)) rescue nil
    elsif @country == 'us' && type == :price
      _tmp = element.respond_to?(:text) ? element.text : nil
      ((_tmp.to_f / 100.to_f).round(2).to_f) rescue nil
    else
      element.respond_to?(:text) ? element.text : nil
    end
  end

  def _get_item_attributes(response, offer_flg=false)
    items = []
    response.each {|item|
      h_item = {}

      if offer_flg
        a_offer = []

        if (item/'Offers/Offer')
          (item/'Offers/Offer').each do |offer|
            _offer = {}
            _offer[:condition] = check_value(offer/'OfferAttributes/Condition')
            _offer[:price] = check_value((offer/'OfferListing/Price/Amount'), :price)
            _offer[:currency] = check_value(offer/'OfferListing/Price/CurrencyCode')
            _offer[:availability] = check_value(offer/'OfferListing/Availability')
            _offer[:availability_type] = check_value(offer/'OfferListing/AvailabilityAttributes/AvailabilityType')
            _offer[:minumum_hours] = check_value(offer/'OfferListing/AvailabilityAttributes/MinimumHours')
            _offer[:maximum_hours] = check_value(offer/'OfferListing/AvailabilityAttributes/MaximumHours')
            a_offer << _offer
          end
        end
        h_item[:offer] = a_offer
      end

      h_item[:offer_url] = nil
      link_attr = (item/'ItemLinks/ItemLink/URL')
      link_attr.each do |lw|
        if lw.text.include?("offer-listing")
          h_item[:offer_url] = lw.text
          break
        end
      end

      h_item[:asin] = check_value((item/'ASIN'))
      h_item[:url] = check_value((item/'DetailPageURL'))

      h_item[:s_img_url] = check_value((item/'SmallImage/URL'), :image)
      h_item[:s_img_height] = check_value((item/'SmallImage/Height'), :size)
      h_item[:s_img_width] = check_value((item/'SmallImage/Width'), :size)
      h_item[:m_img_url] = check_value((item/'MediumImage/URL'), :image)
      h_item[:m_img_height] = check_value((item/'MediumImage/Height'), :size)
      h_item[:m_img_width] = check_value((item/'MediumImage/Width'), :size)

      h_item[:binding] = check_value((item/'ItemAttributes/Binding'), :size)
      h_item[:rank] = check_value((item/'SalesRank'))
      h_item[:brand] = check_value((item/'ItemAttributes/Brand'))
      h_item[:ean] = check_value((item/'ItemAttributes/EAN'))
      h_item[:adult] = check_value((item/'ItemAttributes/IsAdultProduct'))
      h_item[:feature] = check_value((item/'ItemAttributes/Feature'))
      h_item[:title] = check_value((item/'ItemAttributes/Title'))
      h_item[:price] = check_value((item/'ItemAttributes/ListPrice/Amount'), :price)
      h_item[:currency] = check_value((item/'ItemAttributes/ListPrice/CurrencyCode'))
      h_item[:height] = check_value((item/'ItemAttributes/PackageDimensions/Height'))
      h_item[:length] = check_value((item/'ItemAttributes/PackageDimensions/Length'))
      h_item[:weight] = check_value((item/'ItemAttributes/PackageDimensions/Weight'), :weight)
      h_item[:width] = check_value((item/'ItemAttributes/PackageDimensions/Width'))
      h_item[:release] = check_value((item/'ItemAttributes/ReleaseDate'))
      h_item[:lowestnewprice] = check_value((item/'OfferSummary/LowestNewPrice/Amount'), :price)
      h_item[:lowestnewprice_currency] = check_value((item/'OfferSummary/LowestNewPrice/CurrencyCode'))
      h_item[:lowestusedprice] = check_value((item/'OfferSummary/LowestUsedPrice/Amount'), :price)
      h_item[:lowestusedprice_currency] = check_value((item/'OfferSummary/LowestUsedPrice/CurrencyCode'))
      h_item[:totalnew] = check_value((item/'OfferSummary/TotalNew'))
      h_item[:totalused] = check_value((item/'OfferSummary/TotalUsed'))

      items << h_item
    }
    return items
  end

  #def _convert_country(country_cd)
  #	if country_cd == 'jp' then return 0
  #	elsif country_cd == 'us' then return 1
  #	elsif country_cd == 'ca' then return 2
  #	elsif country_cd == 'uk' then return 3
  #	else return
  #	end
  #end

end
