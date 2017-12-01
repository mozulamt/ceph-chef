#
# Cookbook Name:: ceph
# Attributes:: radosgw
#
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
# Copyright 2011, DreamHost Web Hosting
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_attribute 'ceph-chef'

default['ceph']['radosgw']['port'] = 80
# NOTE: If using federated options then look at 'pools' attributes file for federated ports.

default['ceph']['radosgw']['default_url'] = 's3.rgw.ceph.example.com'

# NB: Must create the user 'radosgw' in your upstream Chef process or 'radosgw' user AND group must exists before running
# 'ceph-radosgw-webservice-install.rb'
default['ceph']['radosgw']['rgw_webservice']['enable'] = false
default['ceph']['radosgw']['rgw_webservice']['user'] = 'radosgw'

# IMPORTANT: The civetweb user manual is a good place to look for custom config for civetweb:
# https://github.com/civetweb/civetweb/blob/master/docs/UserManual.md
# Add the options to the single line of the 'frontends etc...'
# NOTE: Change the number of default threads that civetweb uses per node - Default is 100 from civetweb
default['ceph']['radosgw']['civetweb']['num_threads'] = 100

# What IP should civetweb bind to?
# It treats empty string as '0.0.0.0', and binds IPv4-only.
#default['ceph']['radosgw']['civetweb_bindip'] = ''
# Bind to any address on IPv6 AND IPv4.
default['ceph']['radosgw']['civetweb']['bindip'] = '[::]'

# You can pass any civetweb options, as long as they do not contain a comma.
# If they contain a comma, you will trigger http://tracker.ceph.com/issues/20942
default['ceph']['radosgw']['civetweb']['request_timeout_ms'] = '300000'


# Default, this should match civetweb num_threads
default['ceph']['radosgw']['rgw_thread_pool'] = 100

# NOTE: DO NOT append '.log' to these log files because the conf recipe adds it because of the possible use of federation.
default['ceph']['radosgw']['civetweb_access_log_file'] = '/var/log/radosgw/civetweb.access'
default['ceph']['radosgw']['civetweb_error_log_file'] = '/var/log/radosgw/civetweb.error'

# OpenStack Keystone specific
# Will radosgw integrate with OpenStack Keystone - true/false
default['ceph']['radosgw']['keystone']['auth'] = false
default['ceph']['radosgw']['keystone']['admin']['token'] = nil
default['ceph']['radosgw']['keystone']['admin']['url'] = nil
default['ceph']['radosgw']['keystone']['admin']['port'] = 35_357
default['ceph']['radosgw']['keystone']['accepted_roles'] = 'admin Member _member_'
default['ceph']['radosgw']['keystone']['token_cache_size'] = 1000
default['ceph']['radosgw']['keystone']['revocation_interval'] = 1200

# NOTE: For radosgw pools, see pools.rb attributes.

# Number of RADOS handles RGW has access to - system default = 1
default['ceph']['radosgw']['rgw_num_rados_handles'] = 5

# init_style in each major section is allowed so that radosgw or osds or mons etc could be a different OS if required.
# The default is everything on the same OS
default['ceph']['radosgw']['init_style'] = node['ceph']['init_style']

# An admin user needs to be added to RGW. Feel free to change as you see fit or leave it.
# Important: These values must be present or the creation of the admin user will fail!
# NB: IMPORTANT - 'buckets' below is an array of json data and not just the name of a bucket!
default['ceph']['radosgw']['users'] = [
  { 'uid' => 'radosgw', 'name' => 'Admin', 'admin_caps' => 'users=*;buckets=*;metadata=*;usage=*;zone=*', 'access_key' => '', 'secret_key' => '', 'max_buckets' => 0, 'buckets' => [{}] },
  { 'uid' => 'tester', 'name' => 'Tester', 'admin_caps' => 'usage=read; user=read; bucket=*',  'access_key' => '', 'secret_key' => '', 'max_buckets' => 3, 'buckets' => [{}] }
]

default['ceph']['radosgw']['secret_file'] = '/etc/chef/secrets/ceph_chef_rgw'

# No longer used
# default['ceph']['radosgw']['role'] = 'search-ceph-radosgw'

case node['platform_family']
when 'debian'
  packages = ['radosgw', 'radosgw-agent', 'python-boto']
  packages += debug_packages(packages) if node['ceph']['install_debug']
  default['ceph']['radosgw']['packages'] = packages
when 'rhel', 'fedora', 'suse'
  default['ceph']['radosgw']['packages'] = ['ceph-radosgw', 'mailcap'] # NOTE: mailcap should have been a dependency in Ceph. radosgw-agent later
else
  default['ceph']['radosgw']['packages'] = []
end

# If you have a complex federation setup, you might not want this Cookbook to
# generate or apply the JSON for realm/zonegroup/zones.
#
# If so, set this attribute to TRUE.
#
# It will not generate the json files OR try to run radosgw-admin commands
# related to realms, zones, zonegroups.
# The rest of the opinionated choices made by this Cookbook for the NAMING of
# zonegroups/zones will still be made, and will impact the rgw ceph.conf lines.
#
# This is particularly useful to bring up secondary zonegroup/zones, where you
# start by pulling data from the primary.
default['ceph']['radosgw']['manual_federation'] = false
