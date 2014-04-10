# Mutates events for the Flapjack handler. See http://flapjack.io/
#
# This extension is to be used with the Flapjack handler. It allows one to define
# a custom "endpoint" attribute in Sensu, and maps that to its own entity in Flapjack. It
# also resolves Sensu dependencies.
#
# Copyright 2014 Jive Software and contributors.
#
# Released under the same terms as Sensu (the MIT license); see LICENSE for details.

require 'net/http'
require 'json'
require 'sensu-plugin/utils'

module Sensu
  module Extension
    class Metrics < Mutator
      include Sensu::Plugin::Utils

      def definition
        {
          type: 'extension',
          name: 'flapjack',
        }
      end

      def name
        'flapjack'
      end

      def description
        'mutates events for flapjack'
      end

      def run(event)
        @event = Hash[event.map{ |k, v| [k.to_s, v] }]
        logger.debug("flapjack.run(): Handling event - #{@event}")
        map_endpoint
        filter_dependencies
        yield(@event.to_json, 0)
      end

      private

      def event_exists?(client, check)
        begin
          JSON.parse(api_request(:GET, '/event/' + client + '/' + check).body)['status'] == 2
        rescue
          false
        end
      end

      def api_request(method, path, &blk)
        http = Net::HTTP.new(settings['api']['host'], settings['api']['port'])
        req = net_http_req_class(method).new(path)
        if settings['api']['user'] && settings['api']['password']
          req.basic_auth(settings['api']['user'], settings['api']['password'])
        end
        yield(req) if block_given?
        http.request(req)
      end

      def filter_dependencies
        if @event['check'].has_key?('dependencies') or @event['check'].has_key?(:dependencies)
          if @event['check']['dependencies'].is_a?(Array)
            @event['check']['dependencies'].each do |dependency|
              begin
                timeout(2) do
                  check, client = dependency.split('/').reverse
                  e = event_exists?(client || @event['client']['name'], check)
                  if event_exists?(client || @event['client']['name'], check)
                    logger.debug("flapjack.filter_dependencies(): Overriding check status and output for - #{@event}")
                    @event['check']['status'] = 1
                    @event['check']['output'] = "State changed to warning due to parent failing (#{client}/#{check}) - #{@event['check']['output']}"
                  end
                end
              rescue Timeout::Error
                puts 'timed out while attempting to query the sensu api for an event'
              end
            end
          end
        end
      end

      def map_endpoint
        if @event['check']['endpoint']
          @event['client']['name'] = @event['check']['endpoint']
        end
      end

      def logger
        Sensu::Logger.get
      end

    end
  end
end
