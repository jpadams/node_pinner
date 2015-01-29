require 'json'

############ settings #########
###############################
@console_server_name = "localhost"
@groupname           = ARGV[0] # e.g. "PE Master"
@nodesfile           = ARGV[1] # e.g. nodes.txt (1 certname per line)

#$example_newgroup = JSON.generate({"environment_trumps"=>false, "parent"=>"00000000-0000-4000-8000-000000000000", "name"=>"newgroup", "variables"=>{}, "environment"=>"production", "classes"=>{}})

$puppet = '/opt/puppet/bin/puppet'
$credentials = {
  :cacert => %x(#{$puppet} config print localcacert),
  :cert   => %x(#{$puppet} config print hostcert),
  :key    => %x(#{$puppet} config print hostprivkey)
}

############ helpers ##########
###############################
def nodemgr_rest_call (method, service, endpoint, creds, id="", json="", api_ver="v1", console_server=@console_server_name)
  unless id == ""
    id = "/#{id}"
  end

  cmd = "curl -s -k -X #{method} -H 'Content-Type: application/json' \
    -d \'#{json}\' \
    --cacert #{creds[:cacert]} \
    --cert   #{creds[:cert]} \
    --key    #{creds[:key]} \
    https://#{console_server}:4433/#{service}-api/#{api_ver}/#{endpoint}#{id}".delete("\n")
  resp = %x(#{cmd})
  ## don't know if api call succeeded, only if curl worked or not
  if ! $?.success?
    raise "curl rest call failed: #{$?}"
  end
  resp
end

## Get all the nodegroups
def get_nodegroups()
  nodemgr_rest_call("GET", "classifier", "groups", $credentials)
end

## Create a new nodegroup, let the classifier hand us a group ID 
def new_nodegroup(nodegroup_json)
  nodemgr_rest_call("POST", "classifier", "groups", $credentials, id="", nodegroup_json)
end

## Update existing nodegroup by supplying JSON and group ID
def update_nodegroup(nodegroup_json, nodegroup_id)
  nodemgr_rest_call("POST", "classifier", "groups", $credentials, id=nodegroup_id, nodegroup_json)
end

## Get a particular nodegroup by name
def get_nodegroup(nodegroup_name)
  response  = get_nodegroups()
  # Parse the JSON into ruby array of hashes
  JSON.parse(response).each do |record|
    # Return the hash of the nodegroup we were looking for
    if record["name"] == nodegroup_name
      return record
    end
  end
  return nil
end

## Pin the nodes in the nodesfile to the nodegroup named;
## create a new group if the named group doesn't exist yet
def add_pinned_nodes(nodegroup_name, nodesfile)
  # Ruby hash of the nodegroup record
  record  = get_nodegroup(nodegroup_name)
  newrule = []
  if record != nil
    if record["rule"][0] != "or"
      newrule = ["or"]
      newrule << record["rule"]
    else
      newrule = record["rule"]
    end
    # For each line in the file form a pinning rule and add it to the new rule
    File.open(nodesfile, 'r').each_line do |line|
      r = ["=", "name", "#{line.chomp}"]   
      newrule << r
    end
    # Remove any duplicate pinning rules
    record["rule"] = newrule.uniq
    # Turn the hash back into JSON again and make REST call to update nodegroup
    json = JSON.generate(record)
    update_nodegroup(json, record["id"])
    return json
  else
    #smart code to possibly create a new group needed
  end
end

############ action ###########
###############################

## Add the pinned nodes in the text file to the group
## and print out the JSON that is returned.
puts add_pinned_nodes(@groupname, @nodesfile)
