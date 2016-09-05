# Kzdev

kzdev専用のgem。機能は、下記の通り。

* amazon_ecs
* amazon_mws
* mechanize
* rakuten_api
* yahoo_api
* capybara(need phantomjs)
* ebay_api
* rss
* thread

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kzdev'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kzdev

## Usage

### amazon_ecs

```ruby
# 初期化(associate_tag, access_key_id, secret_key, country)
object = AmazonEcsClass.new("mogt0010-22", "AKIAIU3EOUL6ASI2LF3A", "gzFnnLNnGClmjOXY8KTsgKrXSjEJZaIidPcYD/MV", "jp")

# ASIN商品検索
pp object.get_item_description("B00FYHA10I")

# 商品名検索
pp object.search_item("まどまぎ")

# ブラウズノード毎のASIN取得(ブラウズノードを取得してREDIS保存してASINを取得する)
object.save_browsenode
pp object.get_category_asin("Large")
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release` to create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/[my-github-username]/kzdev/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
