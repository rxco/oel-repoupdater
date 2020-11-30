from bs4 import BeautifulSoup
import json
import requests
from requests import get
import os
import shutil
  
epel_url = "https://yum.oracle.com/repo/OracleLinux/OL8/developer/EPEL/x86_64/"
artifactory_local_repo = "https://raulcontreras.jfrog.io/artifactory/OL8/developer/EPEL/x86_64/"
artifactory_latest_repo = "https://raulcontreras.jfrog.io/artifactory/OL8/developer/EPEL/x86_64/epel-latest"
aql_search_endpoint = "https://raulcontreras.jfrog.io/artifactory/api/search/aql"
epel_repository_name = "epel-local"
current_artifacts = {}
local_repo_artifacts = {}
missing_artifacts = {}

results = requests.get(epel_url,)
soup = BeautifulSoup(results.text, "html.parser")

table = soup.findChildren('table')[0]
links = table.findChildren('a', href=True)

# Get updated artifacts from oracle website
count = 0 
for link in links:
    href = link['href']
    name = link.string
    count += 1
    current_artifacts[name] = href

print("f'Got {count} artifacts from EPEL website")

print("Validate existent repos")

custom_header = {
            "X-JFrog-Art-Api": "AKCp8hzD786Q8Mmhfas9s3F7G1JZq8fLyUENeLk5xw6p12QPecTCPu9V7tPuZKxpPxtQxCuoB",
            "Content-Type": "text/plain"}

# we read the AQL query file
with open('query.aql', 'rb') as f:
    aql_file = f.read()

response = requests.post(aql_search_endpoint, data = aql_file, headers = custom_header)

# parse the response to json
json_response = response.json()

# Generate object with current artifacts in local repo
for artifact in json_response['results']:
    local_repo_artifacts[artifact['name']] = artifact['path']


# Check if artifacts from website exist in local repo
files_to_copy_to_latest = {}
files_to_download = {}
for key in current_artifacts.keys():
    if key in local_repo_artifacts.keys():
        print(key)
        print("copy file from existent to latest repo")
        files_to_copy_to_latest[key] = key
    else:
        print(key)
        print("this file is new, needs to be downloaded and pushed to latest")
        files_to_download[key] = key


# we download and push existent artifacts
epel_dir = 'epel/'
os.makedirs(epel_dir)

counts = 0
for artifact in files_to_download.keys():
    counts += 1

    if artifact == "repodata/":
        continue

    url = epel_url + "/getPackage/" + artifact
    r = requests.get(url)
    with open(epel_dir + artifact, 'wb') as f:
        f.write(r.content)


# clean latest repo
response = requests.delete(artifactory_latest_repo, data = {}, headers = custom_header)
if response.status_code == 200:
    print("latest repo deleted")

#push to latest
repo_name = "epel-local-latest"
repo_desc = '{"rclass": "local", "description": "epel artifacts", "packageType:"rpm"}'
for artifact in files_to_download.keys():
    if artifact == "repodata/":
        continue

    file_to_up = {'file': open(epel_dir + artifact, 'rb')}
    req = requests.put(artifactory_latest_repo, files=file_to_up, headers = custom_header)
    if req.status_code == 200:
        print("artifacts uploaded success")

# Copy existent files in local repo to latest
# this will also copy all artifacts first time
# Description: Copy an artifact or a folder to the specified destination. 
# Supported by local repositories only.
# Optionally suppress cross-layout module path translation during copy.
for artifact in files_to_copy_to_latest.keys():
    if artifact == "repodata/":
        continue

    req = requests.post("https://raulcontreras.jfrog.io/artifactory/api/copy/epel-local/" + artifact + "?to=artifactory_latest_repo" , headers = custom_header)
    if req.status_code == 200:
        print("artifacts uploaded success")


# delete folder
shutil.rmtree(epel_dir)






