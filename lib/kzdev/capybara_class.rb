require 'open-uri'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'

class CapybaraClass
  # capybara initialize
  Capybara.run_server = false
  Capybara.javascript_driver = :poltergeist
  Capybara.current_driver = :poltergeist
  Capybara.default_max_wait_time = 5
  include Capybara::DSL

  # コンストラクタ
  # @param [Boolean] image_visible phantomjsの画像読み込み
  # @param [String] ua ユーザエージェント
  # @param [String] proxy プロキシ 例) 127.0.0.1:8118
  # @return [nil]
  def initialize(image_visible, ua, proxy=nil, https=false)
    @@session = nil
    load_option = []
    load_option << '--ignore-ssl-errors=yes'
    load_option << '--web-security=no'

    if !image_visible
      load_option << '--load-images=no'
    end

    if !proxy.nil?
      load_option << '--proxy='+proxy
    end

    if !https
      load_option << '--proxy-type=https'
    else
      load_option << '--proxy-type=http'
    end

    options = {
      js_errors: false,
      timeout: 5,
      phantomjs_logger: StringIO.new,
      logger: nil,
      phantomjs_options: load_option
    }

    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new app, options
    end

    @@session = Capybara::Session.new(:poltergeist)
    @@session.driver.headers = { 'User-Agent' => ua }
  end

  # phantomjsのクロージング
  def session_destroy
    unless @@session.blank?
      sleep 0.1
      #Capybara.reset_sessions!
      sleep 0.1
      @@session.driver.reset!
      sleep 0.1
      @@session.driver.quit
      @@session = nil
      sleep 0.1
    end

  end

  # ajaxの終了待機
  def wait_for_ajax
    sleep JS_WAIT
    Timeout.timeout(Capybara.default_wait_time) do
      break if @@session.evaluate_script('jQuery.active') == nil
      loop until finished_all_ajax_requests?(@@session)
    end
  end

  # jqueryによるAjax通信が終了是非
  def finished_all_ajax_requests?(session)
    @@session.evaluate_script('jQuery.active').zero? #unless session.evaluate_script('jQuery.active').nil?
  end

  # ページ遷移
  # @param [String] url 遷移先のURL
  # @param [Array] auth BASIC認証(user, pass)
  # @return [Boolean] status_codeが200の場合のみtrue
  def visit(url, auth=nil)
    error_flg = false
    if auth
      @@session.driver.basic_authorize(auth[:user], auth[:pass])
    end

    begin
      @@session.visit url
      #wait_for_ajax
      sleep 0.5
    rescue => ex
      #pp ex.message
      error_flg = true
    end

    return !error_flg && @@session.driver.status_code==200 ? 0 : @@session.driver.status_code
  end

  # リファラー経由ページ遷移
  # @param [String] url 遷移先のURL
  # @param [String] referer リファラー
  # @return [Boolean] status_codeが200の場合のみtrue
  def visit_from_referer(url, referer)
    @@session.driver.headers["Referer"] = referer
    error_flg = false

    js = <<EOS
    var link = document.createElement('a');
    link.setAttribute('href', #{url});
    document.body.appendChild(link);

    var evt = document.createEvent('MouseEvents');
    evt.initMouseEvent('click', true, true, window, 1, 1, 1, 1, 1, false, false, false, false, 0, link);
    link.dispatchEvent(evt);
EOS

    begin
      @@session.evaluate_script(js)
      sleep 0.5
    rescue => ex
      pp ex.message
      error_flg = true
    end

    return !error_flg && @@session.driver.status_code==200 ? 0 : @@session.driver.status_code
  end

  def javascript_execute(query)
    @@session.evaluate_script(query)
  end

  def set_referer(referer)
    @@session.driver.headers["Referer"] = referer
  end

  def basic_auth(user, password)
    encoded_login = ["#{user}:#{password}"].pack("m*")
    @@session.driver.headers['Authorization'] = "Basic #{encoded_login}"
  end

  def html
    @@session.body
  end

  def title
    @@session.title
  end

  # 表示されている画面キャプチャを保存
  # @param [String] path キャプチャの保存先
  # @return [nil]
  def capture(path="./capture/#{DateTime.now.strftime('%Y%m%d%H%M%S')}.jpg")
    @@session.save_screenshot(path)
  end

  def find(selector, xpath=false)
    if(xpath)
      @@session.find(:xpath, selector)
    else
      @@session.find(:css, selector)
    end
  end

  def all(selector, xpath=false)
    if(xpath)
      @@session.all(:xpath, selector)
    else
      @@session.all(selector)
    end
  end

  def have_content?(target)
    @@session.has_content?(target)
  end

  def have_selector?(selector, xpath=false)
    if(xpath)
      @@session.has_xpath(selector)
    else
      @@session.has_css(selector)
    end
  end

  def click(target)
    @@session.click_on(target)
  end

  def url?(str)
    begin
      uri = URI.parse(str)
    rescue URI::InvalidURIError
      return false
    end

    return uri.scheme == 'http' || uri.scheme == 'https'
  end
end
