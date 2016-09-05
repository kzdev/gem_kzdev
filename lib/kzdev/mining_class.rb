require 'shellwords'
class MiningClass
	@file_path = nil
	def initialize(file_path)
    @file_path = file_path
	end

  def apache_referrer
    #sh = Shellwords.escape("cat /var/log/nginx/access.log | gawk -F\\\" '$4 !~ \"http://blog.kz-dev.com\" && $4 != \"-\" {system(\"echo \" $4)}' | awk -F/ '{print $3}' | sort | uniq -c | sort -n -r")
    sh = Shellwords.escape("cat /var/log/nginx/access.log | grep localhost")
    system(sh)
  end
end
