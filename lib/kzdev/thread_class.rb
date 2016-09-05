require 'thread'
require 'monitor'
require 'singleton'

class ThreadClass
  include Singleton

  # $B%3%s%9%H%i%/%?(B
  def initialize
    pp "[initialize] thread instance create"

    # mutex syncronize
    #@monitor = Monitor.new
    #@cond = @monitor.new_cond
    @threads = Array.new(MAX_THREAD)

    self.reset
  end

  def reset
    @blocks = []
    @threads.extend(MonitorMixin)
    @threads_available = @threads.new_cond

    @work_queue = SizedQueue.new MAX_THREAD
    @sysexit = false

    @producer_thread = nil
    @consumer_thread = nil
  end

  # $BJBNs=hM}$r$9$k%V%m%C%/$rDI2C(B
  # @param [String] key $B%V%m%C%/4IM}G[Ns(Bkey
  # @param [Block] &block $B=hM}%V%m%C%/(B
  # @return [nil]
  def add(key, params, &block)
    pp "[add] IN. oid: #{block.object_id}"

    @blocks << {key: key, proc: block, params: params}

    pp "[add] OUT."
  end

  # add$B$5$l$?%V%m%C%/$r<B9T(B
  # @param [Boolean] syncronize $BF14|<B9T$N@'Hs(B
  # @return [Hash] $B%V%m%C%/$N<B9T7k2L(B
  #def start(syncronize)
  #  @logger.debug "[start] IN. mode=#{syncronize ? 'syncronize' : 'asyncronize'} blocks=#{@blocks.length}"

  #  # assign thread
  #  @blocks.each do |key, block|
  #    @q.push block.object_id
  #    t = Thread.start do
  #      if !syncronize
  #        begin
  #          Thread.current[:result] = block.call
  #          Thread.current[:key] = key
  #        rescue => e
  #          @logger.error ERROR_VIEW(e)
  #        end
  #        @q.pop
  #      else
  #        @monitor.synchronize do
  #          begin
  #            Thread.current[:result] = block.call
  #            Thread.current[:key] = key
  #          rescue => e
  #            @logger.error ERROR_VIEW(e)
  #          end
  #          @q.pop
  #        end
  #      end
  #    end
  #    @thread_list[t.object_id] = t
  #  end
  #  @blocks = {}

  #  ret = {}
  #  @thread_list.each do |k, v|
  #    next if v.nil?

  #    v.join(THREAD_TIMEOUT)
  #    #ret[v["key"]] = 0 if !ret.key?(v["key"])
  #    #ret[v["key"]] += 1 if v["result"].to_i > 0
  #    ret[v["key"]] = v["result"]

  #    @logger.debug "#{v["key"]} thread finished."

  #    @thread_list.delete(k)
  #    Thread.pass
  #  end
  #  @logger.debug "[start] OUT."
  #  ret
  #end

  # add$B$5$l$?%V%m%C%/$r<B9T(B
  # @return [Hash] $B%V%m%C%/$N<B9T7k2L(B
  def start
    pp "[START] Thread proc count = #{@blocks.size}."

    unless @blocks.size>0
      pp "[END] Thread no proc."
      return
    end

    @consumer_thread = Thread.new do
      loop do
        break if @sysexit && @work_queue.length == 0
        found_index = nil

        @threads.synchronize do
          @threads_available.wait_while do
            @threads.select { |thread| thread.nil? || thread.status == false  ||
                                      thread["finished"].nil? == false}.length == 0
          end
          found_index = @threads.rindex { |thread| thread.nil? || thread.status == false ||
                                                  thread["finished"].nil? == false }
        end

        work = @work_queue.pop

        @threads[found_index] = Thread.new(work[:key]) do
          work[:proc].call work[:params]
          Thread.current["finished"] = true

          @threads.synchronize do
            @threads_available.signal
          end
        end
      end
    end

    @producer_thread = Thread.new do
      @blocks.each do |block|
        @work_queue << block

        @threads.synchronize do
          @threads_available.signal
        end
      end
      @sysexit = true
    end

    @producer_thread.join
    @consumer_thread.join

    @threads.each do |thread|
      thread.join(THREAD_TIMEOUT) unless thread.nil?
    end

    pp "[END] Thread proc"
  end

end
