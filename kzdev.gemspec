# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'version'

Gem::Specification.new do |spec|
  spec.name          = "kzdev"
  spec.version       = Kzdev::VERSION
  spec.authors       = ["kzdev"]
  spec.email         = ["s2000fast@gmail.com"]

  spec.summary       = "kzdev gem"
  spec.description   = "kzdev gem"
  spec.homepage      = "https://bitbucket.org/kzdev01/gem_kzdev"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_dependency "redis"
  spec.add_dependency "mechanize"
  spec.add_dependency "rakuten-api"
  spec.add_dependency "yahoo-api"
  spec.add_dependency "amazon-ecs"
  spec.add_dependency "capybara"
  spec.add_dependency "poltergeist"
  spec.add_dependency "peddler"
  spec.add_dependency "feed-normalizer"
  spec.add_dependency "ebayr"
  spec.add_dependency "ebayapi"
end
