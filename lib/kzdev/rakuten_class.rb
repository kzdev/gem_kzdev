require 'rakuten/api'

class RakutenClass

	# コンストラクタ
	def initialize(app_id, aff_id)
		Rakuten::Api.configure do |options|
			options[:applicationId] = app_id
			options[:affiliateId] = aff_id
		end
	end

	# 楽天市場内の検索
	# @param [Hash] {key => data}
	#   key = keyword, shopCode, itemCode, genreId, tagId
	#   https://webservice.rakuten.co.jp/api/ichibaitemsearch/
	# @return [Hash] 検索結果
	def searchIchiba(params)
		res = Rakuten::Api.get(Rakuten::Api::Ichiba::Search, params)
		data = []

		res["Items"].each do |item|
			_data = {}
			_data = setItemData({}, item)

			data << _data
		end
		data
	end

	# ランキング市場内の検索
	# @param [Hash] {key => data}
	#   key = genreId, age(10: 10代, 20: 20代..), sex(0: 男, 1: 女)
	#   https://webservice.rakuten.co.jp/api/ichibaitemranking/
	# @return [Hash] 検索結果
	def searchRanking(params)
		res = Rakuten::Api.get(Rakuten::Api::Ichiba::Ranking, params)
		data = []

		res["Items"].each do |item|
			_data = {}
			_data = setItemData({}, item)

			data << _data
		end
		data
	end

	# 楽天ブックス内の検索
	# @param [Hash] {key => data}
	#   key = keyword, booksGenreId, isbnjan, availability(0: すべての商品, 1: 在庫あり, 5: 予約受付中, 6: メーカ在庫確認)
	#   https://webservice.rakuten.co.jp/api/bookstotalsearch/
	# @return [Hash] 検索結果
	def searchBooks(params)
		res = Rakuten::Api.get(Rakuten::Api::Books::TotalSearch, params)
		data = []

		res["Items"].each do |item|
			_data = setItemData({}, item)
			data << _data
		end
		data
	end

	def setItemData(_data, item)
		# 商品情報
		_data[:author]					= (item["Item"]["author"] rescue '')	# 著書名
		_data[:title]						= (item["Item"]["itemName"] rescue '')	# 商品タイトル
		_data[:code]						= (item["Item"]["itemCode"] rescue '')	# 商品コード
		_data[:artist_name]			= (item["Item"]["artistName"] rescue '')	# アーティスト名
		_data[:publisher_name]	= (item["Item"]["publisherName"] rescue '')	# 出版社名
		_data[:label]						= (item["Item"]["label"] rescue '') # 発売元名(CD/DVD/GAAMEのみ)
		_data[:isbn]						= (item["Item"]["isbn"] rescue '')	# ISBN
		_data[:jan]							= (item["Item"]["jan"] rescue '')	# JAN
		_data[:list_price]			= (item["Item"]["listPrice"] rescue '')	# 定価
		_data[:discount_rate]		= (item["Item"]["discountRate"] rescue '')	# 割引率
		_data[:hardware]				= (item["Item"]["hardware"] rescue '') # 対応機種(ゲームのみ)
		_data[:os]							= (item["Item"]["os"] rescue '') # 対応OS(ソフトウェアのみ)
		_data[:image]						= (item["Item"]["smallImageUrls"][0]["imageUrl"] rescue '')
		_data[:price]						= (item["Item"]["itemPrice"] rescue '')	# 商品価格
		_data[:description]			= (item["Item"]["itemCaption"] rescue '')	# 商品説明文
		_data[:item_url]				= (item["Item"]["itemUrl"] rescue '')	# 商品URL
		_data[:availability]		= (item["Item"]["availability"] rescue '')	# 販売可能フラグ(0: 販売不可能, 1: 販売可能)
		_data[:shipping_flag]		= (item["Item"]["postageFlag"] rescue '')	# 送料フラグ(0: 送料込, 1: 送料別)
		_data[:url]							= (item["Item"]["affiliateUrl"] rescue '')	# アフェリエイト用URL

		# 店舗情報
		_data[:shop_name]				= (item["Item"]["shopName"] rescue '')	# 店舗名
		_data[:shop_code]				= (item["Item"]["shopCode"] rescue '')	# 店舗コード
		_data[:shop_url]				= (item["Item"]["shopUrl"] rescue '')	# 店舗URL

		_data
	end
end
