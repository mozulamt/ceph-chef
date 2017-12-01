#
# Author:: Hans Chris Jones <chris.jones@lambdastack.io>
# Cookbook Name:: ceph
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

# Federated version of creating keys and setting up radosgw.

# NOTE: This recipe *MUST* be included in the 'radosgw' recipe and not used as a stand alone recipe!

service_type = node['ceph']['mon']['init_style']

# NOTE: This base_key can also be the bootstrap-rgw key (ceph.keyring) if desired but the default is the admin key. Just change it here.
base_key = "/etc/ceph/#{node['ceph']['cluster']}.client.admin.keyring"

# NOTE: If multisite-replication == true then one zonegroup and more than one zone will need to exist. Can support
# additional zonegroups if some base logic is changed below but for now just one zone.
# NOTE: If multisite-replication == false then one zonegroup and one zone. For example, the one zonegroup plus each zone will
# create a zonegroup-zone combination which is both zonegroup and zone so that the same set of data and it's structure can
# be used for both scenarios.
# NOTE: The zonegroup.json file is a little different for no multisite-replication since there is a one-to-one zonegroup/zone
# combination. The zone.json is the same for both scenarios.

if node['ceph']['pools']['radosgw']['federated_enable']
  node['ceph']['pools']['radosgw']['federated_zone_instances'].each do |inst|
    # Client name for RGW ops
    rgwclient="client.radosgw.#{inst['zonegroup']}-#{inst['name']}"
    rgwclient_opt="--name=#{rgwclient}"

    # Keyring
    keyring = if node['ceph']['pools']['radosgw']['federated_multisite_replication']
                "/etc/ceph/#{node['ceph']['cluster']}.client.radosgw.keyring"
              else
                "/etc/ceph/#{node['ceph']['cluster']}.#{rgwclient}.keyring"
              end

    file "/var/log/radosgw/#{node['ceph']['cluster']}.#{rgwclient}.log" do
      owner node['ceph']['owner']
      group node['ceph']['group']
    end

    directory "/var/lib/ceph/radosgw/#{node['ceph']['cluster']}-radosgw.#{inst['zonegroup']}-#{inst['name']}" do
      owner node['ceph']['owner']
      group node['ceph']['group']
      mode node['ceph']['mode']
      recursive true
      action :create
      not_if { ::File.directory?("/var/lib/ceph/radosgw/#{node['ceph']['cluster']}-radosgw.#{inst['zonegroup']}-#{inst['name']}") }
    end

    # Check for existing keys first!
    new_key = ''
    ruby_block "check-radosgw-secret-#{inst['name']}" do
      block do
        fetch = Mixlib::ShellOut.new("sudo ceph auth get-key #{rgwclient} 2>/dev/null")
        fetch.run_command
        key = fetch.stdout
        unless key.to_s.strip.empty?
          new_key = ceph_chef_save_radosgw_inst_secret(key, "#{inst['zonegroup']}-#{inst['name']}")
        end
      end
    end

    # If an initial key exists then this will run - for shared keyring file
    unless !new_key.to_s.strip.empty?
      new_key = ceph_chef_radosgw_inst_secret("#{inst['zonegroup']}-#{inst['name']}")
      # One last sanity check on the key
      new_key = nil if new_key.to_s.strip.length != 40
    end
    execute 'update-ceph-radosgw-secret' do
      command lazy { "sudo ceph-authtool #{keyring} #{rgwclient_opt} --add-key=#{new_key} --cap osd 'allow rwx' --cap mon 'allow rwx'" }
      only_if { !new_key.to_s.strip.empty? }
      only_if { ::File.size?("#{keyring}") }
      sensitive true if Chef::Resource::Execute.method_defined? :sensitive
    end

    execute 'write-ceph-radosgw-secret' do
      command lazy { "sudo ceph-authtool #{keyring} --create-keyring #{rgwclient_opt} --add-key=#{new_key} --cap osd 'allow rwx' --cap mon 'allow rwx'" }
      only_if { !new_key.to_s.strip.empty? }
      not_if { ::File.size?("#{keyring}") }
      sensitive true if Chef::Resource::Execute.method_defined? :sensitive
    end

    # If no initial key exists then this will run
    execute 'generate-client-radosgw-secret' do
      command <<-EOH
        sudo ceph-authtool --create-keyring #{keyring} #{rgwclient_opt} --gen-key --cap osd 'allow rwx' --cap mon 'allow rwx'
      EOH
      creates keyring
      not_if { ceph_chef_radosgw_inst_secret("#{inst['zonegroup']}-#{inst['name']}") }
      not_if { ::File.size?("#{keyring}") }
      notifies :create, "ruby_block[save-radosgw-secret-#{inst['name']}]", :immediately
      sensitive true if Chef::Resource::Execute.method_defined? :sensitive
    end

    # Allow all zone keys
    execute 'update-client-radosgw-secret' do
      command <<-EOH
        sudo ceph-authtool #{keyring} #{rgwclient_opt} --gen-key --cap osd 'allow rwx' --cap mon 'allow rwx'
      EOH
      not_if "sudo grep #{rgwclient} #{keyring}"
      sensitive true if Chef::Resource::Execute.method_defined? :sensitive
    end

    execute "update-#{rgwclient}-auth" do
      command <<-EOH
        sudo ceph -k #{base_key} auth add #{rgwclient} -i #{keyring}
      EOH
      not_if "ceph auth list | grep #{rgwclient}"
      sensitive true if Chef::Resource::Execute.method_defined? :sensitive
    end

    # Saves the key to the current node attribute
    ruby_block "save-radosgw-secret-#{inst['name']}" do
      block do
        fetch = Mixlib::ShellOut.new("sudo ceph-authtool #{keyring} #{rgwclient_opt}  --print-key")
        fetch.run_command
        key = fetch.stdout
        ceph_chef_save_radosgw_inst_secret(key.delete!("\n"), "#{inst['zonegroup']}-#{inst['name']}")
      end
      action :nothing
    end

    # Create a realm if needed
    realm = inst['realm'] || 'gold'
    radosgw_admin_cmd="sudo radosgw-admin #{rgwclient_opt}"
    execute "realm-create-#{inst['zonegroup']}" do
      command <<-EOH
        #{radosgw_admin_cmd} realm create --rgw-realm=#{realm} --default
      EOH
      only_if { node['ceph']['radosgw']['manual_federation'] == false }
      not_if "#{radosgw_admin_cmd} realm list | grep '\"#{realm}\"'"
    end

    # Add the zonegroup and zone files and remove the default root pools
    if node['ceph']['pools']['radosgw']['federated_multisite_replication'] == true
      template "/etc/ceph/#{inst['zonegroup']}-zonegroup.json" do
        source 'radosgw-zonegroup.json.erb'
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
        not_if { ::File.size?("/etc/ceph/#{inst['zonegroup']}-zonegroup.json") }
        variables lazy {
          {
            :name => node['ceph']['pools']['radosgw']['federated_zonegroups'][0],
            :master_zone => node['ceph']['pools']['radosgw']['federated_zonegroups'][0] + "-" + node['ceph']['pools']['radosgw']['federated_master_zone'],
            :zones => node['ceph']['pools']['radosgw']['federated_zone_instances'],
            :endpoints => [
              "http://#{node['ceph']['pools']['radosgw']['federated_zone_instances'][0]['url']}:#{node['ceph']['pools']['radosgw']['federated_zone_instances'][0]['port']}/",
            ],
            :s3hostnames => node['ceph']['pools']['radosgw']['s3hostnames'],
            :s3hostnames_website => node['ceph']['pools']['radosgw']['s3hostnames_website'],
          }
        }
      end

      template "/etc/ceph/#{inst['zonegroup']}-zonegroup-map.json" do
        source 'radosgw-zonegroup-map.json.erb'
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
        not_if { ::File.size?("/etc/ceph/#{inst['zonegroup']}-zonegroup-map.json") }
        variables lazy {
          {
            :name => node['ceph']['pools']['radosgw']['federated_zonegroups'][0],
            :master_zone => node['ceph']['pools']['radosgw']['federated_zonegroups'][0] + "-" + node['ceph']['pools']['radosgw']['federated_master_zone'],
            :zones => node['ceph']['pools']['radosgw']['federated_zone_instances'],
            :endpoints => [
              "http://#{node['ceph']['pools']['radosgw']['federated_zone_instances'][0]['url']}:#{node['ceph']['pools']['radosgw']['federated_zone_instances'][0]['port']}/",
            ],
            :s3hostnames => node['ceph']['pools']['radosgw']['s3hostnames'],
            :s3hostnames_website => node['ceph']['pools']['radosgw']['s3hostnames_website'],
          }
        }
      end

      zonegroup = (inst['zonegroup']).to_s
      zone = (inst['name']).to_s
      zonegroup_file = "/etc/ceph/#{zonegroup}-zonegroup.json"
      zonegroup_map_file = "/etc/ceph/#{zonegroup}-zonegroup-map.json"
    else
      template "/etc/ceph/#{inst['zonegroup']}-#{inst['name']}-zonegroup.json" do
        source 'radosgw-zonegroup.json.erb'
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
        not_if { ::File.size?("/etc/ceph/#{inst['zonegroup']}-#{inst['name']}-zonegroup.json") }
        variables lazy {
          {
            :name => "#{inst['zonegroup']}-#{inst['name']}",
            :master_zone => "#{inst['zonegroup']}-#{inst['name']}",
            :zones => node['ceph']['pools']['radosgw']['federated_zone_instances'],
            :endpoints => [
              "http://#{inst['url']}:#{inst['port']}/",
            ],
            :s3hostnames => Array(inst['s3hostnames']),
            :s3hostnames_website => Array(inst['s3hostnames_website']),
          }
        }
      end

      template "/etc/ceph/#{inst['zonegroup']}-#{inst['name']}-zonegroup-map.json" do
        source 'radosgw-zonegroup-map.json.erb'
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
        not_if { ::File.size?("/etc/ceph/#{inst['zonegroup']}-#{inst['name']}-zonegroup-map.json") }
        variables lazy {
          {
            :name => "#{inst['zonegroup']}-#{inst['name']}",
            :master_zone => "#{inst['zonegroup']}-#{inst['name']}",
            :zones => node['ceph']['pools']['radosgw']['federated_zone_instances'],
            :endpoints => [
              "http://#{inst['url']}:#{inst['port']}/",
            ],
            :s3hostnames => Array(inst['s3hostnames']),
            :s3hostnames_website => Array(inst['s3hostnames_website']),
          }
        }
      end

      zonegroup = "#{inst['zonegroup']}"
      zone = "#{inst['zonegroup']}-#{inst['name']}"
      zonegroup_file = "/etc/ceph/#{zone}-zonegroup.json"
      zonegroup_map_file = "/etc/ceph/#{zone}-zonegroup-map.json"
    end

    if node['ceph']['pools']['radosgw']['federated_enable_zonegroups_zones']
      template "/etc/ceph/#{zone}-zone.json" do
        source 'radosgw-federated-zone.json.erb'
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
        not_if { ::File.size?("/etc/ceph/#{zone}-zone.json") }
        variables lazy {
          {
            :zonegroup => (zonegroup).to_s,
            :zone => (zone).to_s,
            :secret_key => '',
            :access_key => ''
          }
        }
      end

      execute "zonegroup-set-#{zonegroup}" do
        command <<-EOH
          #{radosgw_admin_cmd} zonegroup set --infile=#{zonegroup_file} --rgw-zonegroup=#{zonegroup}
        EOH
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
        not_if "#{radosgw_admin_cmd} zonegroup get --rgw-zonegroup=#{zonegroup} |grep '\"name\": \"#{zonegroup}\""
      end

      # zonegroup-map was removed in 10.2.10
      #execute "zonegroup-map-set-#{zonegroup}" do
      #  command <<-EOH
      #    #{radosgw_admin_cmd} zonegroup-map set --infile #{zonegroup_map_file} --rgw-zonegroup=#{zonegroup}
      #  EOH
      #  only_if { node['ceph']['radosgw']['manual_federation'] == false }
      #  not_if "#{radosgw_admin_cmd} zonegroup-map get | grep #{zonegroup}"
      #end

      # execute 'remove-default-zonegroup' do
      #  command lazy { "rados -p .#{zonegroup}.rgw.root rm zonegroup_info.default" }
      #  ignore_failure true
      #  only_if { node['ceph']['radosgw']['manual_federation'] == false }
      #  not_if "rados -p .#{zonegroup}.rgw.root ls | grep zonegroup_info.default"
      # end

      # execute 'remove-default-zone' do
      #  command lazy { "rados -p .#{zone}.rgw.root rm zone_info.default" }
      #  ignore_failure true
      #  only_if { node['ceph']['radosgw']['manual_federation'] == false }
      #  not_if "rados -p .#{zone}.rgw.root ls | grep zone_info.default"
      # end

      execute "zone-set-#{zone}" do
        command <<-EOH
          #{radosgw_admin_cmd} zone set --rgw-zone=#{zone} --infile /etc/ceph/#{zone}-zone.json
        EOH
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
        not_if "#{radosgw_admin_cmd} zone get --rgw-zone=#{zone} | |grep '\"name\": \"#{zone}\""
      end

      execute "create-zonegroup-defaults-#{zonegroup}" do
        # zonegroup-map was removed in 10.2.10
        # #{radosgw_admin_cmd} zonegroup-map update --rgw-zonegroup=#{zonegroup}
        command <<-EOH
          #{radosgw_admin_cmd} zonegroup default --rgw-zonegroup=#{zonegroup}
        EOH
        only_if { node['ceph']['radosgw']['manual_federation'] == false }
      end
    end

    # execute "update-zonegroupmap-#{zone}" do
    #  command <<-EOH
    #    #{radosgw_admin_cmd} zonegroupmap update
    #  EOH
    #  only_if { node['ceph']['radosgw']['manual_federation'] == false }
    # end

    # FUTURE: Update the keys for the zones. This will allow each one to sync with the other.
    # ceph_chef_secure_password(20)
    # ceph_chef_secure_password(40)
    # Will need to create radosgw-admin user with --system so that each zone has a system user so that they can
    # communicate with each other for replication

    # This is only here as part of completeness. The service_type is not really needed because of defaults.
    ruby_block "radosgw-finalize-#{zone}" do
      block do
        ['done', service_type].each do |ack|
          ::File.open("/var/lib/ceph/radosgw/#{node['ceph']['cluster']}-radosgw.#{zone}/#{ack}", 'w').close
        end
      end
      not_if { ::File.file?("/var/lib/ceph/radosgw/#{node['ceph']['cluster']}-radosgw.#{zone}/done") }
    end
  end
end
