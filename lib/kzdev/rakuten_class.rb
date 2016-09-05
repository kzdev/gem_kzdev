require 'rakuten/api'

class RakutenClass

	# $B%3%s%9%H%i%/%?(B
	def initialize(app_id, aff_id)
		Rakuten::Api.configure do |options|
			options[:applicationId] = app_id
			options[:affiliateId] = aff_id
		end
	end

	# $B3ZE7;T>lFb$N8!:w(B
	# @param [Hash] {key => data}
	#   key = keyword, shopCode, itemCode, genreId, tagId
	#   https://webservice.rakuten.co.jp/api/ichibaitemsearch/
	# @return [Hash] $B8!:w7k2L(B
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

	# $B%i%s%-%s%0;T>lFb$N8!:w(B
	# @param [Hash] {key => data}
	#   key = genreId, age(10: 10$BBe(B, 20: 20$BBe(B..), sex(0: $BCK(B, 1: $B=w(B)
	#   https://webservice.rakuten.co.jp/api/ichibaitemranking/
	# @return [Hash] $B8!:w7k2L(B
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

	# $B3ZE7%V%C%/%9Fb$N8!:w(B
	# @param [Hash] {key => data}
	#   key = keyword, booksGenreId, isbnjan, availability(0: $B$9$Y$F$N>&IJ(B, 1: $B:_8K$"$j(B, 5: $BM=Ls<uIUCf(B, 6: $B%a!<%+:_8K3NG'(B)
	#   https://webservice.rakuten.co.jp/api/bookstotalsearch/
	# @return [Hash] $B8!:w7k2L(B
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
		# $B>&IJ>pJs(B
		_data[:author]					= (item["Item"]["author"] rescue '')	# $BCx=qL>(B
		_data[:title]						= (item["Item"]["itemName"] rescue '')	# $B>&IJ%?%$%H%k(B
		_data[:code]						= (item["Item"]["itemCode"] rescue '')	# $B>&IJ%3!<%I(B
		_data[:artist_name]			= (item["Item"]["artistName"] rescue '')	# $B%"!<%F%#%9%HL>(B
		_data[:publisher_name]	= (item["Item"]["publisherName"] rescue '')	# $B=PHG<RL>(B
		_data[:label]						= (item["Item"]["label"] rescue '') # $BH/Gd85L>(B(CD/DVD/GAAME$B$N$_(B)
		_data[:isbn]						= (item["Item"]["isbn"] rescue '')	# ISBN
		_data[:jan]							= (item["Item"]["jan"] rescue '')	# JAN
		_data[:list_price]			= (item["Item"]["listPrice"] rescue '')	# $BDj2A(B
		_data[:discount_rate]		= (item["Item"]["discountRate"] rescue '')	# $B3d0zN((B
		_data[:hardware]				= (item["Item"]["hardware"] rescue '') # $BBP1~5!<o(B($B%2!<%`$N$_(B)
		_data[:os]							= (item["Item"]["os"] rescue '') # $BBP1~(BOS($B%=%U%H%&%'%"$N$_(B)
		_data[:image]						= (item["Item"]["smallImageUrls"][0]["imageUrl"] rescue '')
		_data[:price]						= (item["Item"]["itemPrice"] rescue '')	# $B>&IJ2A3J(B
		_data[:description]			= (item["Item"]["itemCaption"] rescue '')	# $B>&IJ@bL@J8(B
		_data[:item_url]				= (item["Item"]["itemUrl"] rescue '')	# $B>&IJ(BURL
		_data[:availability]		= (item["Item"]["availability"] rescue '')	# $BHNGd2DG=%U%i%0(B(0: $BHNGdIT2DG=(B, 1: $BHNGd2DG=(B)
		_data[:shipping_flag]		= (item["Item"]["postageFlag"] rescue '')	# $BAwNA%U%i%0(B(0: $BAwNA9~(B, 1: $BAwNAJL(B)
		_data[:url]							= (item["Item"]["affiliateUrl"] rescue '')	# $B%"%U%'%j%(%$%HMQ(BURL

		# $BE9J^>pJs(B
		_data[:shop_name]				= (item["Item"]["shopName"] rescue '')	# $BE9J^L>(B
		_data[:shop_code]				= (item["Item"]["shopCode"] rescue '')	# $BE9J^%3!<%I(B
		_data[:shop_url]				= (item["Item"]["shopUrl"] rescue '')	# $BE9J^(BURL

		_data
	end
end
