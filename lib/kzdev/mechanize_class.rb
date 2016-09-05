require 'mechanize'
require 'open-uri'

class MechanizeClass
	def initialize(ua=USER_AGENT)
		@@agent = Mechanize.new
		@@agent.user_agent = ua
	end

	def visit(url, auth=nil)
		if auth
			@@agent.auth(auth.user_id, auth.password)
		end
		@@page = @@agent.get(url)
	end

	def click(text)
		ret = nil
		link = @@page.link_with(:text => text)
		ret = link.click if link
		@@page = ret if ret
		ret
	end

	def html
		@@page.body.toutf8
	end

	def url
		@@page.uri.to_s
	end

	def title
		@@page.title
	end

	# return []
	def search(css)
		@@page.search(css)
	end

	# return first elment
	def at(css)
		@@page.at(css)
	end

	def form(form_name, form_param, form_value)
		@@page = @@page.form_with(:name => form_name) do |form|
			form_param.each_with_index do |ff, i|
				form[ff] = form_value[i]
			end
		end.submit
	end
end

