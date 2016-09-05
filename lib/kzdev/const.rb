require 'active_support/time'

DEBUG = nil # 1: on nil: off
RETRY_COUNT = 3

# SCRAPE
USER_AGENT	= "Mozilla/5.0 (iPhone; CPU iPhone OS 6_0 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10A403 Safari/8536.25"
USER_AGENT_IE	=  "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.2; Win64; x64; Trident/6.0)"
MAX_COLLECT	= 8
WAIT_RANGE	= 1
JS_WAIT	= 1.5
EXEC_INTERVAL = 30.minutes.ago

# CACHE
CACHE_PATH	= "./tmp/cache_/"
EXEC_FORCE = false # false: キャッシュを利用 true: キャッシュを利用しない

# ERROR
def ERROR_VIEW(e) return "class: #{e.class} message: #{e.message} backtrace: #{e.backtrace}" end

# THREAD
MAX_THREAD	= 8
THREAD_TIMEOUT = 300

# LOG
LOG_FILE		= Rails.root.join('log').join('task.log').to_s

# REDIS
CACHE_PREFIX = "scrape_cache_"
ERROR_PREFIX = "scrape_error_"
TAG_PREFIX = "tag_"
LASTTIME_PREFIX = "scrape_lasttime_"

# browse_node保存用
AMAZON_NODE_PREFIX = "amazon_node_"
AMAZON_ASIN_PREFIX = "amazon_asin"
AMAZON_SKU_PREFIX = "amazon_sku"
AMAZON_REPORT_PREFIX = "amazon_report_"

# AMAZON
AMAZON_WARNING = 5
AMAZON_ERROR = 20
