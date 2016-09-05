require 'feed-normalizer'
require 'open-uri'

class RssClass
	@rss = nil
	def initialize(url)
		url_escape = URI.escape(url)
		@@rss = FeedNormalizer::FeedNormalizer.parse(open(url_escape))
	end

	def entry
		@@rss.entries
	end

	def count
		@@rss.entries.size
	end
end
