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

node['ceph']['radosgw']['packages'].each do |pck|
  v = ceph_exactversion(pck)
  package pck do
    action node['ceph']['package_action']
    version v if v
  end
end

platform_family = node['platform_family']

cookbook_file '/usr/local/bin/radosgw-admin2' do
  source 'radosgw-admin2'
  owner 'root'
  group 'root'
  mode 0755
end

cookbook_file '/usr/local/bin/rgw_s3_api.py' do
  source 'rgw_s3_api.py'
  owner 'root'
  group 'root'
  mode 0755
end

include_recipe 'ceph-chef::install'
