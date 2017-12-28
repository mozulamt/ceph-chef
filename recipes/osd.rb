#
# Author:: Hans Chris Jones <chris.jones@lambdastack.io>
# Cookbook Name:: ceph
# Recipe:: osd
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

# NOTE: Example of an OSD device to add. You can find other examples in the OSD attribute file and the
# environment file. The device and the journal should be the same IF you wish the data and journal to be
# on the same device (ceph default). However, if you wish to have the data on device by itself (i.e., HDD)
# and the journal on a different device (i.e., SSD) then give the cooresponding device name for the given
# entry (device or journal). The command 'ceph-disk prepare' will keep track of partitions for journals
# so DO NOT create a device with partitions already configured and then attempt to use that as the journal:
# device value. Journals are raw devices (no file system like xfs).
#
# "osd": {
#    "devices": [
#        {
#            "type": "hdd",
#            "data": "/dev/sdb",
#            "data_type": "hdd",
#            "journal": "/dev/sdf",
#            "journal_type": "ssd",
#            "encrypted": false,
#            "status": ""
#        }
#    ]
# }

# Standard Ceph UUIDs:
# NOTE: Ceph OSD uuid type 4fbd7e29-9d25-41b8-afd0-062c0ceff05d
# NOTE: dmcrypt Ceph OSD uuid type 4fbd7e29-9d25-41b8-afd0-5ec00ceff05d
# NOTE: Ceph Journal uuid type 45b0969e-9b03-4f30-b4c6-b4b80ceff106
# NOTE: dmcrypt Ceph Journal uuid type 45b0969e-9b03-4f30-b4c6-5ec00ceff106
#
GPT_UUID_TYPE_CEPH_OSD_PLAIN = '4fbd7e29-9d25-41b8-afd0-062c0ceff05d'
GPT_UUID_TYPE_CEPH_OSD_DMCRYPT = '4fbd7e29-9d25-41b8-afd0-5ec00ceff05d'
GPT_UUID_TYPE_CEPH_JOURNAL_PLAIN = '45b0969e-9b03-4f30-b4c6-b4b80ceff106'
GPT_UUID_TYPE_CEPH_JOURNAL_DMCRYPT = '45b0969e-9b03-4f30-b4c6-5ec00ceff106'

include_recipe 'ceph-chef'
include_recipe 'ceph-chef::osd_install'

# Disk utilities used
package 'gdisk' do
  action :upgrade
end

package 'cryptsetup' do
  action :upgrade
  only_if { node['ceph']['osd']['dmcrypt'] }
end

# Create the scripts directory within the /etc/ceph directory. This is not standard Ceph. It's included here as
# a place to hold helper scripts mainly for OSD and Journal maintenance
directory '/etc/ceph/scripts' do
  mode node['ceph']['mode']
  recursive true
  action :create
  not_if { ::File.directory?("/etc/ceph/scripts") }
end

# Add ceph_journal.sh helper script to all OSD nodes and place it in /etc/ceph
cookbook_file '/etc/ceph/scripts/ceph_journal.sh' do
  source 'ceph_journal.sh'
  mode node['ceph']['mode']
  not_if { ::File.file?("/etc/ceph/scripts/ceph_journal.sh") }
end

include_recipe 'ceph-chef::bootstrap_osd_key'

# Calling ceph-disk prepare is sufficient for deploying an OSD
# After ceph-disk prepare finishes, the new device will be caught
# by udev which will run ceph-disk-activate on it (udev will map
# the devices if dm-crypt is used).
# IMPORTANT:
#  - Always use the default path for OSD (i.e. /var/lib/ceph/osd/$cluster-$id)
if node['ceph']['osd']['devices']
  devices = node['ceph']['osd']['devices']

  devices = Hash[(0...devices.size).zip devices] unless devices.is_a? Hash

  devices.each do |index, osd_device|
    if !node['ceph']['osd']['devices'][index]['status'].nil? && node['ceph']['osd']['devices'][index]['status'] == 'deployed'
      Log.info("osd: osd device '#{osd_device}' has already been setup.")
      next
    end
    if node['ceph']['osd']['devices'][index]['data'].nil? || node['ceph']['osd']['devices'][index]['journal'].nil?
      Log.warn("osd: osd device '#{osd_device}' missing data & journal attributes")
      next
    end

    # The default backend store for Luminous is bluestore to specify another
    # OSD storage mechanism the 'backendstore' attribute need to be set.
    # More options can be added here as they become available.
    store = osd_device['backendstore'] == 'filestore' ? '--filestore' : ''
    # if the 'encrypted' attribute is true then apply flag. This will encrypt the data at rest.
    # IMPORTANT: More work needs to be done on solid key management for very high security environments.
    dmcrypt = osd_device['encrypted'] == true ? '--dmcrypt' : ''

    # The proplem below is that we want to know what partition# was created (if
    # any) by 'ceph-disk prepare'. If the disk was empty, it will probably be
    # #1. If the disk was NOT empty, then it's the next free number. Then it's
    # figuring out what the correct naming of the partition is. It might be
    # just a numeric suffix, or a 'p'+suffix or '-part'+suffix.
    #
    # prepare takes a raw device for both data & journal and makes partitions
    # on both as needed.
    #
    # list takes a raw device as well, not a partition, also drop the /dev/ prefix.
    #
    # activate takes a PARTITION if applicable.
    #
    # As a hack for now, if the device is MAYBE partitionable, try to run
    # 'ceph-disk list' on it and take the first entry that matches 'ceph data'
    #
    # * Maybe partitionable defined as:
    # - exists in /sys/block/$X/
    # - /sys/block/$X/ext_range is >1 (TODO)
    # - /sys/block/$X/capability does not have 0x0200 set (TODO: GENHD_FL_NO_PART_SCAN)
    #
    # TODO: Fix this for future things that might have more than one data
    # volume on a disk.
    # TODO: we do readlink for the moment to resolve symlinks, but we should
    # resolve the rdev major/minor to get the canonical name.
    #
    # Other unworkable solutions:
    # Chef resource ordering means that we'd have to try and scan the partition
    # table below & after running ceph-disk and figure out the difference.
    sgdisk_partitions = (1..31).to_a.map { |x| "-i#{x}" }.join(' ') # Lots of parts to check.
    execute "ceph-disk-prepare on #{osd_device['data']}" do
      command <<-EOH
        data=$(readlink -f #{osd_device['data']})
        data_nodev=${data#/dev/}
        echo "ceph-disk BEFORE"
        f1=$(mktemp --tmpdir ceph-disk-prepare.1.XXXXXXXXXX)
        f2=$(mktemp --tmpdir ceph-disk-prepare.2.XXXXXXXXXX)
        test -e /sys/block/$data_nodev && ceph-disk list $data_nodev | tee $f1
        ceph-disk -v prepare --cluster #{node['ceph']['cluster']} #{store} #{dmcrypt} --fs-type #{node['ceph']['osd']['fs_type']} $data #{osd_device['journal']}
        echo "ceph-disk AFTER"
        test -e /sys/block/$data_nodev && ceph-disk list $data_nodev | tee $f2
        # Do a trivial compare, find the only new line that matches 'ceph data'
        test -e /sys/block/$data_nodev && dev=$(comm --nocheck-order -13 $f1 $f2 | awk '/ceph data/{print $1}')
        test -z "${dev}" && dev=$data # fallback
        echo "ceph-disk activate $dev"
        ceph-disk -v activate $dev
        sleep 3
        echo rm -f $f1 $f2
      EOH
      # NOTE: The meaning of the uuids used here are listed above
      not_if "sgdisk #{sgdisk_partitions} #{osd_device['data']} | grep -i #{GPT_UUID_TYPE_CEPH_OSD_PLAIN}" unless dmcrypt
      not_if "sgdisk #{sgdisk_partitions} #{osd_device['data']} | grep -i #{GPT_UUID_TYPE_CEPH_OSD_DMCRYPT}" if dmcrypt
      # Only if there is no 'ceph *' found in the label. The recipe os_remove_zap should be called to remove/zap
      # all devices if you are wanting to add all of the devices again (if this is not the initial setup)
      not_if "sgdisk --print #{osd_device['data']} | egrep -sq '^ .*ceph'"
      action :run
      notifies :create, "ruby_block[save osd_device status #{index}]", :immediately
    end

    # Add this status to the node env so that we can implement recreate and/or delete functionalities in the future.
    ruby_block "save osd_device status #{index}" do
      block do
        node.normal['ceph']['osd']['devices'][index]['status'] = 'deployed'
        # node.save
      end
      action :nothing
      # only_if "ceph-disk list 2>/dev/null | grep 'ceph data' | grep #{osd_device['data']}"
    end

    # NOTE: Do not attempt to change the 'ceph journal' label on a partition. If you do then ceph-disk will not
    # work correctly since it looks for 'ceph journal'. If you want to know what Journal is mapped to what OSD
    # then do: (cli below will output the map for you - you must be on an OSD node)
    # ceph-disk list
  end
else
  Log.info("node['ceph']['osd']['devices'] empty")
end
