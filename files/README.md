## release.asc
This file is the new ceph repo key. This file only changes if there is a serious issue such as a breach in the repo. If the key has to be replaced then there should be a recipe that does that and updates any mirrored repos that may be impacted. This key is updated locally so as to not have to pull it each time. This is very important for those installs behind proxies etc.

## ceph-rest-api.service (systemd specific)
Systemd file for ceph-rest-api. It does not currently map to ceph.target since that should be upstream and it maybe using the Hammer release and systemd is only used in Infernalis and above.
