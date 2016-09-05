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

	# $B%3%s%9%H%i%/%?(B
	# @param [String] name $B%?%9%/L>>N(B
	# @param [Boolean] image_visible $B%$%a!<%8<hF@$NM-L5(B
	# @param [String] ua $B%f!<%6%(!<%8%'%s%H(B
	# @param [String] cache_path $B%-%c%C%7%e$NJ]B8@h(B
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

	# $B;XDj$5$l$?%-!<%o!<%I$NB8:_$r3NG'(B
	# @param [Hash] keywords $B8!:w$9$k%-!<%o!<%I(B{id, keyword}
	# @param [String] _xpath $BK\J8It$N;XDj(BXPATH
	# @param [Integer] mid Redis$B>e$G%-!<$K$J$k(BID
	# @return [Integer] 1: $B@.8y(B 0: $B<:GT(B
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

			# REDIS$B$KEPO?:Q$_$N%-%c%C%7%e$+$i8!:w(B
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
					# $B8+$D$+$C$F$$$l$P(Bv:1, $BL$H/8+$N>l9g(Bv:0
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

	# $B;XDj$5$l$?%3%s%F%s%D$r<hF@(B
	# @param [String] type :xpath$B$^$?$O(B:css$B$H;XDj(B
	# @param [String] path $B;XDj%Q%9(B
	# @param [Integer] mid Redis$B>e$G%-!<$K$J$k(BID
	# @param [Hash] auth :user_id and :password, or :click
	# @return Integer] 1: $B@.8y(B 0: $B<:GT(B
	def get_content(type, path, mid, auth=nil)
		ret = nil
		@@news_counter = 0
		@@logger.info "[get_content] IN. mid: #{mid} auth: #{auth} path: #{path}"

		return if self.delete_cache(mid)==0 && @@redis.keys(CACHE_PREFIX+mid.to_s+"*").size>0

		# [TODO] login or page next($B:#$N$H$3$m$OF|7P?7J9@lMQ(B)
		if auth && auth.key?(:user_id)
			@@logger.info "try login user_id: #{auth[:user_id]} password: #{auth[:password]}"

			# $B4{$K%m%0%$%sCf$N>l9g$O<:GT$9$k$O$:(B
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

			# $B%j%9%H<hF@(B
			url_list.each do |url|
				# enable click
				url = convert_url(url)
				pp url if DEBUG
				# $BM-8z$J(BURL$B$+%A%'%C%/(B
				next if !self.url?(url)
				@@logger.info url

				# $B!V9-9p$r%9%-%C%W!W$^$?$O!VG'>Z!W0J30$O(Bopen-uri$B$G<hF@(B
				# open-uri$B$K$h$k<hF@$NJ}$,9bB.$J$?$a(B
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

	# $B%3%s%F%s%D$r%-%c%C%7%e$7(BREDIS$BEPO?(B
	# @param [String] html HTML$B%\%G%#(B
	# @param [Integer] mid REDIS$B$N%-!<(B
	# @param [String] title $B%Z!<%8%?%$%H%k(B
	# @param [String] url HTML$B$N(BURL
	# @param [String] file_name $B%-%c%C%7%e$H$7$FJ];}$9$k%U%!%$%kL>(B
	# @return Integer] 1: $B@.8y(B 0: $B<:GT(B
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

	# $B%-%c%C%7%e:o=|(B
	# @param [Integer] mid REDIS$B$N%-!<(B
	# @return Integer] 1: $B@.8y(B 0: $B<:GT(B
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

	# $B%?%08!:w7k2L$r:o=|(B
	# @param [Integer] mid REDIS$B$N%-!<(B
	# @return Integer] 1: $B@.8y(B 0: $B<:GT(B
	def delete_tag(mid)
		@@redis.keys(CACHE_PREFIX+mid.to_s+"*").each do |key|
			tag_keys = @@redis.hkeys(key).select{|_k| _k.include?(TAG_PREFIX)}
			tag_keys.each do |tag|
				@@redis.hdel(key, tag)
			end
		end
	end

end
