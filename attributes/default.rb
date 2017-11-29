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

# NOTE: IMPORTANT: Specific attributes related to different ceph roles (i.e., mon, radosgw, osd, cephfs)
# will be found in those attribute files.

# Change this if you want a different cluster name other than the default of ceph
default['ceph']['cluster'] = 'ceph'

# Set default keyring locations. These can be overriden by setting them after this loads.
default['ceph']['keyring']['global'] = '/etc/ceph/$cluster.$name.keyring'
# NB: Could leave others set to '' and template would skip or do the same for global
default['ceph']['keyring']['mon'] = '/etc/ceph/$cluster.$name.keyring'
default['ceph']['keyring']['mds'] = '/etc/ceph/$cluster.$name.keyring'
default['ceph']['keyring']['rgw'] = '/etc/ceph/$cluster.client.radosgw'
default['ceph']['keyring']['res'] = '/etc/ceph/$cluster.client.restapi'
default['ceph']['keyring']['adm'] = '/etc/ceph/$cluster.client.admin.keyring'
default['ceph']['keyring']['osd'] = '/var/lib/ceph/osd/$cluster-$id/keyring'

default['ceph']['tuning']['osd_op_threads'] = 8
default['ceph']['tuning']['osd_recovery_op_priority'] = 1
default['ceph']['tuning']['osd_recovery_max_active'] = 1
default['ceph']['tuning']['osd_max_backfills'] = 1

default['ceph']['system']['scheduler']['device']['ceph']['priority'] = 7
default['ceph']['system']['scheduler']['device']['ceph']['class'] = 'idle'
default['ceph']['system']['scheduler']['device']['type'] = 'deadline'

# Beginning in Kraken ceph-mgr is available. Change to true if running Kraken or higher and you wish to enable it.
# Should run on mon nodes. Does not require a quorum like mons.
default['ceph']['mgr']['enable'] = false

# Allows for experimental things such SHEC Erasure Coding plugin in releases below Jewel.
# This will go into the global section of the ceph.conf on all nodes
default['ceph']['experimental']['enable'] = false
default['ceph']['experimental']['features'] = ['shec']

# This section controls which repo branch to use but is not in repo.rb because it also allows for changing of
# Ceph version information that is used for conditionals used in the recipes to KEEP them here.
default['ceph']['branch'] = 'stable' # Can be stable, testing or dev.

# Major release version to install or gitbuilder branch
# Must set this outside of this cookbook!
# default['ceph']['version'] = 'jewel'
#
# Exact version within release to install
# Must set this outside of this cookbook!
# MUST be valid within node['ceph']['version']
# default['ceph']['exactversion'] = '10.2.10'

# What should the package action be?
default['ceph']['package_action'] = :install

default['ceph']['init_style'] = case node['platform']
                                when 'ubuntu'
                                  'upstart'
                                else
                                  'sysvinit'
                                end

default['ceph']['owner'] = 'ceph'
default['ceph']['group'] = 'ceph'
default['ceph']['mode'] = 0o0750

# Override these in your environment file or here if you wish. Don't put them in the 'ceph''config''global' section.
# The public and cluster network settings are critical for proper operations.
default['ceph']['network']['public']['cidr'] = ['10.121.1.0/24']
default['ceph']['network']['cluster']['cidr'] = ['10.121.2.0/24']

# Tags are used to identify nodes for searching (unless using environments - see below)
# IMPORTANT
default['ceph']['admin']['tag'] = 'ceph-admin'
default['ceph']['radosgw']['tag'] = 'ceph-rgw'
default['ceph']['mon']['tag'] = 'ceph-mon'
default['ceph']['rbd']['tag'] = 'ceph-rbd'
default['ceph']['osd']['tag'] = 'ceph-osd'
default['ceph']['mds']['tag'] = 'ceph-mds'
default['ceph']['restapi']['tag'] = 'ceph-restapi'

# These belong here for downstream dynamically built environment json files.
default['ceph']['radosgw']['logs']['ops']['enable'] = false
default['ceph']['radosgw']['logs']['usage']['enable'] = false
default['ceph']['radosgw']['debug']['logs']['enable'] = true
default['ceph']['radosgw']['gc']['max_objects'] = 32
default['ceph']['radosgw']['gc']['obj_min_wait'] = 7200
default['ceph']['radosgw']['gc']['processor_max_time'] = 3600
default['ceph']['radosgw']['gc']['processor_period'] = 3600

# Search by environment
# Setting this to true will search for nodes by environment/attributes instead of roles/tags.
# By default, the environment searched is the value of `node.environment`, though this can
# be overriden by setting `node['ceph']['search_environment']` to the desired environment.
default['ceph']['search_by_environment'] = false

# Set the max pid since Ceph creates a lot of threads and if using with OpenStack then...
default['ceph']['system']['sysctls'] = ['kernel.pid_max=4194303', 'fs.file-max=26234859']

default['ceph']['install_debug'] = false
default['ceph']['encrypted_data_bags'] = false

default['ceph']['install_repo'] = true
default['ceph']['btrfs'] = false

# Install the netaddr gem
default['ceph']['netaddr_install'] = true

case node['platform_family']
when 'debian'
  packages = ['ceph-common', 'python-pycurl']
  packages += debug_packages(packages) if node['ceph']['install_debug']
  default['ceph']['packages'] = packages
when 'rhel', 'fedora'
  packages = ['ceph', 'yum-plugin-priorities.noarch', 'python-pycurl']
  packages += debug_packages(packages) if node['ceph']['install_debug']
  default['ceph']['packages'] = packages
else
  default['ceph']['packages'] = []
end

# This is a complete list of packages that would get an exactversion suffix.
# Without -dbg/-debug suffix.
default['ceph']['versioned_packages'] = %w[
  ceph
  ceph-base
  ceph-common
  ceph-fuse
  ceph-mds
  ceph-mgr
  ceph-mon
  ceph-osd
  ceph-resource-agents
  ceph-test
  libcephfs2
  libcephfs-dev
  libcephfs-java
  libcephfs-jni
  librados2
  librados-dev
  libradosstriper1
  libradosstriper-dev
  librbd1
  librbd-dev
  librgw2
  librgw-dev
  python3-ceph-argparse
  python3-cephfs
  python3-rados
  python3-rbd
  python3-rgw
  python-ceph
  python-cephfs
  python-rados
  python-rbd
  python-rgw
  radosgw
  rados-objclass-dev
  rbd-fuse
  rbd-mirror
  rbd-nbd
]
