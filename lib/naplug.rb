require 'rubygems'
require 'naplug/plugin'

module Naplug

  class Error < StandardError; end

  module ClassMethods

    attr_reader :plugins

    class DuplicatePlugin < StandardError; end

    def plugin(tag = :main, &block)
      @plugins = Hash.new unless @plugins
      raise DuplicatePlugin, "duplicate definition of #{tag}" if @plugins.key? tag
      @plugins[tag] = create_plugin tag, block
    end

    def tags
      self.plugins.keys
    end

    private

    def create_plugin(tag,block)
      plugin = Plugin.new tag, block

      module_eval do
        # setup <tag> methods for quick access to plugins
        define_method "#{tag}".to_sym do
          @plugins[tag]
        end
        # setup <tag>! methods to involke exec! on a given plugin; it is desitable for this to accept arguments (future feature?)
        define_method "#{tag}!".to_sym do
          self.exec! tag
        end
      end
      plugin
    end

  end

  module InstanceMethods

    attr_reader :plugins

    def initialize(args = {})
      @plugins = Hash.new
      plugins!

      @_args = Hash.new
      args! args

      @_runinng = nil
    end

    def args
      @_args
    end

    def args!(args)
      @_args.merge! args
      @plugins.each do |tag,plugin|
        plugin_args = args.key?(tag) ? args[tag] : {}
        shared_args = args.select { |t,a| not @plugins.keys.include? t }
        plugin.args! shared_args.merge! plugin_args
      end
    end

    def to_str(tag = default_plugin.tag)
      s_format = perfdata ? '%s: %s | %s' : '%s: %s'
      s_array = perfdata ? [@plugins[tag].status,@plugins[tag].output,perfdata(tag).strip] : [@plugins[tag].status,@plugins[tag].output]
      s_format % s_array
    end

    def exec!(tag = default_plugin.tag)
      exec tag
      eval tag
      exit tag
    end

    def exec(tag = default_plugin.tag)
      rexec @plugins[tag]
    end

    def eval(tag = default_plugin.tag)
      @plugins[tag].eval
    end

    def eject!(payload = nil)
      o = case payload
            when String then payload
            when Exception then "#{payload.backtrace[1][/.+:\d+/]}: #{payload.message}"
            else nil
              caller[0][/.+:\d+/]
          end
      print "UNKNOWN: plugin eject! in %s\n" % [o]
      Kernel::exit 3
    end

    private

    def rexec(plug)
      if plug.has_plugins?
        plug.plugins.each_value { |p| rexec p }
      else
        plexec plug
      end
    end

    def plexec(p)
      begin
        @_running = p.tag
        instance_exec p, &p.block
        @_running = nil
      rescue Naplug::Error => e
          p.status.unknown!
          p.output! "#{e.backtrace[1][/[^\/]+:\d+/]}: #{e.message}"
      rescue => e
        p.status.unknown!
        p.output! e.message
        p.payload! e
      ensure
        @_runinng = nil
      end
    end

    def plugins!
      self.class.plugins.each do |tag,plugin|
        @plugins[tag] = Plugin.new tag, plugin.block
      end
    end

    def default_plugin
      return @plugins[:main] if @plugins.key? :main
      return @plugins[@plugins.keys[0]] if @plugins.size == 1
      nil
    end

    def perfdata(tag = default_plugin.tag)
      plugin = @plugins[tag]
      if plugin.has_plugins?
        plugin.plugins.values.map do |plug|
          plug.perfdata
        end.join(' ').gsub(/^\s+$/,'').strip!
      else
        plugin.perfdata
      end
    end

    def exit(tag = default_plugin.tag)
      print "%s\n" % [to_str(tag)]
      Kernel::exit @plugins[tag].status.to_i
    end

    def method_missing(method, *args, &block)
      message = "undefined instance variable or method #{method}"
      case @_runinng
        when nil?
          begin; raise Naplug::Error, message; rescue => e; eject! e ; end
        else
          raise Naplug::Error, message
      end
    end

    def respond_to_missing?(method, *)
      @plugins.keys? method || super
    end

  end

  def self.included(klass)
    klass.send :include, InstanceMethods
    klass.extend ClassMethods
  end

end