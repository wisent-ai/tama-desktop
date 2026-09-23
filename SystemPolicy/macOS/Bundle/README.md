# Bundle resources of the Tama system policy

`Scripts/build-app.sh` installs `ai.wisent.tama.system-policy.plist` as the
launch daemon, installs `TamaNetworkFilter-Info.plist` into the network filter
system extension, and signs the helpers with the two entitlement files. They
live apart from the Objective-C sources, which are compiled from `..`.
