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

def debug_packages(packages)
  packages.map { |x| x + debug_ext }
end

def debug_ext
  case node['platform_family']
  when 'debian'
    '-dbg'
  when 'rhel', 'fedora'
    '-debug'
  else
    ''
  end
end

def cephfs_requires_fuse
  # What kernel version supports the given Ceph version tunables
  # http://ceph.com/docs/master/rados/operations/crush-map/
  min_versions = {
    'hammer' => 3.18
  }
  min_versions.default = 3.18

  # If we are on linux and have a new-enough kernel, allow kernel mount
  if node['os'] == 'linux' && Gem::Version.new(node['kernel']['release'].to_f) >= Gem::Version.new(min_versions[node['ceph']['version']])
    false
  else
    true
  end
end

def ceph_exactversion(pkg)
  pkg_ver = nil
  return pkg_ver unless node['ceph']['versioned_packages'].include?(pkg.gsub(/-(dbg|debug)$/,''))
  if node['ceph']['exactversion'] then
    if node['ceph']['exactversion'].respond_to?(:has_key?) then
      pkg_ver = node['ceph']['exactversion']['default'] if node['ceph']['exactversion'].has_key?('default')
      pkg_ver = node['ceph']['exactversion'][pkg] if node['ceph']['exactversion'].has_key?(pkg)
    else
      pkg_ver = node['ceph']['exactversion']
    end
  end
end

# The default backend store for Luminous is bluestore to specify another
# OSD storage mechanism the 'objectstore' attribute need to be set.
# More options can be added here as they become available.
def osd_objectstore(store)
  case store
  when nil
    # allow Ceph default to be used
    return ''
  when 'bluestore', 'filestore'
    # allow specific known stores
  else
    # allow everything else, but warn
    Chef::Log.warn("Unknown OSD objectstore: #{store}, trying to guess")
  end
  return "--#{store}"
end
