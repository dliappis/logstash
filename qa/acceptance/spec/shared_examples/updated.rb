# Licensed to Elasticsearch B.V. under one or more contributor
# license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch B.V. licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'net/http'
require 'json'
require 'open3'

require_relative '../spec_helper'
require          'logstash/version'
require 'pry'
ARTIFACTS_API = "https://artifacts-api.elastic.co/v1/versions"

# TODO move to debian/redhat etc as they are arch specific ...
def logstash_download_url(version, arch, artifact_type)
  filename = "logstash-#{version}-#{arch}.#{artifact_type}"
  dest_filename = "logstash-#{version}.#{artifact_type}"
  return { url: "https://artifacts.elastic.co/downloads/logstash/#{filename}", dest: File.join(ROOT, 'qa', dest_filename) }
end

def latest_logstash_version(target_version="7.17")
  uri = URI(ARTIFACTS_API)

  response = Net::HTTP.get(uri)
  versions_data = JSON.parse(response)

  filtered_versions = versions_data["versions"].select { |v| v.start_with?(target_version) }

  return filtered_versions.max_by { |v| Gem::Version.new(v) }
end

def download_logstash_artifact(version, arch, artifact_type)
  url, dest = logstash_download_url(version, arch, artifact_type).values_at(:url, :dest)

  Open3.popen3("curl -fsSL --retry 5 --retry-delay 5 #{url} -o #{dest}") do |stdin, stdout, stderr, wait_thr|
    error = stderr.read
    raise "Error: #{error} while downloading artifact from #{url}" unless error.empty?
  end
end


# This test checks if the current package could used to update from the latest version released.
RSpec.shared_examples "updated" do |logstash|
  before(:all) {
    #unset to force it using bundled JDK to run LS
    logstash.run_command("unset LS_JAVA_HOME")
    logstash.uninstall
  }
  after(:all)  do
    logstash.stop_service # make sure the service is stopped
    logstash.uninstall #remove the package to keep uniform state
  end

  before(:each) do    
    # TODO after this is moved elsewhere e.g. in debian, amd64 and deb aren't needed anymore
    download_logstash_artifact(latest_logstash_version(), "amd64", "deb")
    options = {:version => latest_logstash_version(), :snapshot => false, :base => "./", :skip_jdk_infix => true }
    logstash.install(options) # make sure latest version is installed
  end

  it "can be updated and run on #{logstash.hostname}" do
    pending('Cannot install on OS') if logstash.hostname == 'oel-6'
    expect(logstash).to be_installed
    # Performing the update
    logstash.install({:version => LOGSTASH_VERSION})
    expect(logstash).to be_installed
    # starts the service to be sure it runs after the upgrade
    with_running_logstash_service(logstash) do
      expect(logstash).to be_running
    end
  end
end
