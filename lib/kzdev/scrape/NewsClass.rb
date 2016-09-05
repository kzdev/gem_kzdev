require 'active_support'
require 'active_support/time'
require 'kconv'
require 'moji'
require 'open-uri'
require 'nokogiri'

require "const.rb"
require "CapybaraClass"
require "ThreadClass"
require "RedisClass"
require "RssClass"
require "MechanizeClass"
require "LoggerModule"

class ScrapeClass < CapybaraClass
	include LoggerModule
	attr_reader :name

	# コンストラクタ
	# @param [String] name タスク名称
	# @param [Boolean] image_visible イメージ取得の有無
	# @param [String] ua ユーザエージェント
	# @param [String] cache_path キャッシュの保存先
	def initialize(name, image_visible=false, ua=USER_AGENT, cache_path=CACHE_PATH)
		@@logger = logger
		@@logger.debug("#{name} ScrapeClass initialize.")

		# paraent construct call
		super(image_visible, ua)

		@name = name
		@@ua = ua
		@@news_counter = 0
		@@redis = RedisClass.instance()
		@@cache_path = cache_path
	end

	def login()

	end

	# 指定されたキーワードの存在を確認
	# @param [Hash] keywords 検索するキーワード{id, keyword}
	# @param [String] _xpath 本文部の指定XPATH
	# @param [Integer] mid Redis上でキーになるID
	# @return [Integer] 1: 成功 0: 失敗
	def analyze(keywords, _xpath, mid)
		ret = nil
		all_total = 0

		@@logger.debug "[analyze] IN. keywords: #{keywords.size} xpath: #{_xpath} mid: #{mid}"

		begin
			if @@redis.keys(CACHE_PREFIX+mid.to_s+"_*").size==0
				@@logger.info "[analyze] OUT. No Contents."
				return
			end

			thread = ThreadClass.instance

			# REDISに登録済みのキャッシュから検索
			@@redis.keys(CACHE_PREFIX+mid.to_s+"*").each do |key|
				total = 0
				filename = @@redis.hget(key, :file_name)
				pp filename if DEBUG

				url = @@redis.hget(key, :url)
				url = convert_url(url)
				pp url if DEBUG

				html = open(filename, "r:binary").read
				node = Nokogiri::HTML(html.toutf8, nil, 'utf-8')

				_xpath.gsub!("\"","\'")
				contents = node.xpath(_xpath).text
				pp "contents: #{contents.size} byte" if DEBUG
				contents.gsub!("\n", "")
				contents.gsub!("\r", "")
				contents.gsub!(" ", "")

				keywords.each do |_id, _words|
					_proc = Proc.new {
						ret = 0
						_words.each do |_word|
							ret+=1 if contents.include?(_word)
						end
						ret
					}
					thread.add(_id, &_proc)
				end

				result = thread.start(false)

				# tag block join
				result.each do |k, v|
					next if v.nil?
					pp k if DEBUG
					# 見つかっていればv:1, 未発見の場合v:0
					total += v.to_i
					if v.to_i>0
						@@redis.hset key, TAG_PREFIX+k.to_s, v.to_i
					end
				end

				@@logger.debug "hit url: #{url}" if total>0
				@@logger.debug "hit filename: #{filename}" if total>0
				@@redis.hset key, :found, total

				all_total += total
			end

			ret = all_total
		rescue => e
			@@logger.error ERROR_VIEW(e)
			ret = e.message
		end

		@@logger.debug "[analyze] OUT. found: #{all_total}"
		ret
	end

	# 指定されたコンテンツを取得
	# @param [String] type :xpathまたは:cssと指定
	# @param [String] path 指定パス
	# @param [Integer] mid Redis上でキーになるID
	# @param [Hash] auth :user_id and :password, or :click
	# @return Integer] 1: 成功 0: 失敗
	def get_content(type, path, mid, auth=nil)
		ret = nil
		@@news_counter = 0
		@@logger.info "[get_content] IN. mid: #{mid} auth: #{auth} path: #{path}"

		return if self.delete_cache(mid)==0 && @@redis.keys(CACHE_PREFIX+mid.to_s+"*").size>0

		# [TODO] login or page next(今のところは日経新聞専用)
		if auth && auth.key?(:user_id)
			@@logger.info "try login user_id: #{auth[:user_id]} password: #{auth[:password]}"

			# 既にログイン中の場合は失敗するはず
			begin
				@@session.find(:xpath, "//*[@class='bs-special bs-paper']").click
				wait_for_ajax
				@@logger.info "move news list ok."

				@@session.find(:xpath, "//*[@class='idForm']").set(auth[:user_id])
				@@session.find(:xpath, "//*[@class='pwForm']").set(auth[:password])
				@@session.find(:xpath, "//*[@class='cmnc-submit']/li/input").click
				wait_for_ajax
				@@logger.info "login ok."

			rescue => e
				@@logger.debug "login failed. #{e.message}"
				@@redis.hset(ERROR_PREFIX+mid.to_s, :error, e.message)
				@@redis.hset(ERROR_PREFIX+mid.to_s, :created_date, Time.now.strftime("%Y%m%d%H%M%S"))
				return
			end

			begin
				err_msg = @@session.find(:xpath, "//*[@class='cmnc-error-title']").text
				unless err_msg.blank?
					@@redis.hset(ERROR_PREFIX+mid.to_s, :error, err_msg)
					@@redis.hset(ERROR_PREFIX+mid.to_s, :created_date, Time.now.strftime("%Y%m%d%H%M%S"))
				end
			rescue
			end

		end

		begin
			nodes = @@session.all(type, path)
		rescue => e
			@@redis.hset(ERROR_PREFIX+mid.to_s, :error, e.message)
			@@redis.hset(ERROR_PREFIX+mid.to_s, :created_date, Time.now.strftime("%Y%m%d%H%M%S"))
		end

		if nodes.size>0
			url_list = nodes.map {|node| node[:href] unless node[:href].blank? }
			nodes = nil

			# リスト取得
			url_list.each do |url|
				# enable click
				url = convert_url(url)
				pp url if DEBUG
				# 有効なURLかチェック
				next if !self.url?(url)
				@@logger.info url

				# 「広告をスキップ」または「認証」以外はopen-uriで取得
				# open-uriによる取得の方が高速なため
				if auth && auth.key?(:user_id)
					begin
						self.visit url
					rescue => e
						@@logger.error e.message
						next
					end

					html = self.html
					title = self.title.toutf8
				else
					agent = MechanizeClass.new(@@ua)
					begin
						agent.visit url
					rescue => e
						@@logger.error e.message
						next
					end

					agent.click(auth[:click]) if auth && auth.key?(:click)

					title = agent.title.toutf8
					html = agent.html
				end

				save_cache(html, mid, title, url, "#{@@cache_path}#{SecureRandom.uuid}.html")
			end
			ret = 1
		else
			#@@redis.hset(ERROR_PREFIX+mid.to_s, :error, "Newslist not found.")
			#@@redis.hset(ERROR_PREFIX+mid.to_s, :created_date, Time.now.strftime("%Y%m%d%H%M%S"))

			@@logger.error "[get_content] No news list Element."

			ret = 0
		end
		@@logger.debug "[get_content] OUT."
		ret
	end

	def get_rss(url, mid)
		obj = RssClass.new(url)
		obj.entry.each do |node|
			charset = nil
			pp "rss_url: #{node.url}" if DEBUG

			next if node.url.blank?

			begin
				@@logger.info "rss_url: #{node.url}"
				html = open(node.url, "User-Agent"=>@@ua) do |f|
					charset = f.charset
					f.read
				end
			rescue => e
				#@@redis.hset(ERROR_PREFIX+mid.to_s, :error, e.message)
				#@@redis.hset(ERROR_PREFIX+mid.to_s, :created_date, Time.now.strftime("%Y%m%d%H%M%S"))
				@@logger.error "[get_rss] url: #{node.url} message: #{e.message}"
				next
			end

			save_cache(html, mid, node.title, node.url, "#{@@cache_path}#{SecureRandom.uuid}.html")
		end
	end

	def convert_url(url)
		uri = URI.parse(@@session.current_url)
		return if uri.blank? || url.blank?
		if !url.include?("http")
			url = uri.scheme + "://" +  uri.host + url
		end
		URI.escape(url)
	end

	# コンテンツをキャッシュしREDIS登録
	# @param [String] html HTMLボディ
	# @param [Integer] mid REDISのキー
	# @param [String] title ページタイトル
	# @param [String] url HTMLのURL
	# @param [String] file_name キャッシュとして保持するファイル名
	# @return Integer] 1: 成功 0: 失敗
	def save_cache(html, mid, title, url, file_name)
		ret = nil
		@@logger.debug "[save_cache] IN. mid: #{mid} url: #{url} file_name: #{file_name}"
		begin
			File.open(file_name, "wb") {|f|
				f.puts html.toutf8
			}
			@@redis.hset CACHE_PREFIX+mid.to_s+"_"+@@news_counter.to_s, :url, url
			@@redis.hset CACHE_PREFIX+mid.to_s+"_"+@@news_counter.to_s, :title, title
			@@redis.hset CACHE_PREFIX+mid.to_s+"_"+@@news_counter.to_s, :created_date, Time.now.strftime("%Y%m%d%H%M%S")
			@@redis.hset CACHE_PREFIX+mid.to_s+"_"+@@news_counter.to_s, :file_name, file_name
			@@news_counter += 1
			ret = 1
		rescue => e
			@@logger.error ERROR_VIEW(e)
			ret = 0
		end
		@@logger.debug "[save_cache] OUT."
		ret
	end

	# キャッシュ削除
	# @param [Integer] mid REDISのキー
	# @return Integer] 1: 成功 0: 失敗
	def delete_cache(mid)
		del = 0
		#@@logger.debug.w "[delete_cache] IN."

		@@redis.keys(CACHE_PREFIX+mid.to_s+"*").each do |key|
			created = @@redis.hget(key, :created_data)

			if !EXEC_FORCE && (created && DateTime.parse(created) > EXEC_INTERVAL)
				@@logger.info "[delete_cache] SKIP. LASTTIME is #{created}."
				next
			end

			begin
				# deleted cache data
				file_name = @@redis.hget(key, :file_name)
				File.unlink file_name.to_s rescue ""
				@@redis.del key
				@@redis.del ERROR_PREFIX+mid.to_s

				del += 1
			rescue => e
				@@logger.error ERROR_VIEW(e)
			end
		end
		#@@logger.debug.w "[delete_cache] OUT."
		del
	end

	# タグ検索結果を削除
	# @param [Integer] mid REDISのキー
	# @return Integer] 1: 成功 0: 失敗
	def delete_tag(mid)
		@@redis.keys(CACHE_PREFIX+mid.to_s+"*").each do |key|
			tag_keys = @@redis.hkeys(key).select{|_k| _k.include?(TAG_PREFIX)}
			tag_keys.each do |tag|
				@@redis.hdel(key, tag)
			end
		end
	end

end
