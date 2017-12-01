#
# Author: Hans Chris Jones <chris.jones@lambdastack.io>
# Copyright 2017, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'ceph-chef'
include_recipe 'ceph-chef::mgr_install'

# NOTE: Only run this recipe after Ceph is running and only on Mon nodes.

if node['ceph']['mgr']['enable']
  # NOTE: Ceph sets up structure automatically so the only thing needed is to enable and start the service
  # robbat2: No it doesn't!

  cluster = node['ceph']['cluster']
 
  mgrdir = "/var/lib/ceph/mgr/#{cluster}-#{node['hostname']}"
  directory mgrdir do
    owner node['ceph']['owner']
    group node['ceph']['group']
    mode node['ceph']['mode']
    recursive true
    action :create
    not_if { ::File.directory?(mgrdir) }
  end

  keyring = "#{mgrdir}/keyring"
  execute 'format ceph-mgr-secret as keyring' do
    command lazy { "ceph auth get-or-create mgr.#{node['hostname']} mon 'allow profile mgr' osd 'allow *' mds 'allow *' > #{keyring}" }
    user node['ceph']['owner']
    group node['ceph']['group']
    #only_if { ceph_chef_mgr_secret }
    not_if { ::File.size?(keyring) }
    sensitive true if Chef::Resource::Execute.method_defined? :sensitive
  end

  service_type = node['ceph']['mgr']['init_style']
  ruby_block 'mgr-finalize' do
    block do
      ['done', service_type].each do |ack|
        ::File.open("#{mgrdir}/#{ack}", 'w').close
      end
    end
    not_if { ::File.file?("#{mgrdir}/done") }
  end

  service 'ceph_mgr' do
    case node['ceph']['mgr']['init_style']
    when 'upstart'
      service_name 'ceph-mgr-all-starter'
      provider Chef::Provider::Service::Upstart
    else
      service_name "ceph-mgr@#{node['hostname']}"
    end
    action [:enable, :start]
    supports :restart => true
  end
end
