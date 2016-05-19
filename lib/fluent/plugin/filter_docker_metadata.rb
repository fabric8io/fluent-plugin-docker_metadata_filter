#
# Fluentd Docker Metadata Filter Plugin - Enrich Fluentd events with Docker
# metadata
#
# Copyright 2015 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
module Fluent
  class DockerMetadataFilter < Fluent::Filter
    Fluent::Plugin.register_filter('docker_metadata', self)

    config_param :docker_url, :string,  :default => 'unix:///var/run/docker.sock'
    config_param :cache_size, :integer, :default => 100
    config_param :container_id_regexp, :string, :default => '(\w{64})'

    def self.get_metadata(container_id)
      begin
        Docker::Container.get(container_id).info
      rescue Docker::Error::NotFoundError
        nil
      end
    end

    def initialize
      super
    end

    def configure(conf)
      super

      require 'docker'
      require 'json'
      require 'lru_redux'

      Docker.url = @docker_url

      @cache = LruRedux::ThreadSafeCache.new(@cache_size)
      @container_id_regexp_compiled = Regexp.compile(@container_id_regexp)
    end

    def filter_stream(tag, es)
      new_es = es
      container_id = tag.match(@container_id_regexp_compiled)
      if container_id && container_id[0]
        container_id = container_id[0]
        metadata = @cache.getset(container_id){DockerMetadataFilter.get_metadata(container_id)}

        if metadata
          new_es = MultiEventStream.new

          es.each {|time, record|
            record['docker'] = {
              'id' => metadata['id'],
              'name' => metadata['Name'],
              'container_hostname' => metadata['Config']['Hostname'],
              'image' => metadata['Config']['Image'],
              'image_id' => metadata['Image'],
              'labels' => metadata['Config']['Labels']
            }
            new_es.add(time, record)
          }
        end
      end

      return new_es
    end
  end

end
