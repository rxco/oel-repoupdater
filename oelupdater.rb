# Oelupdater
# frozen_string_literal: true
require 'httparty'
require 'json'
require 'nokogiri'
require 'open-uri'

require 'pry'
require 'zip'

class Oelupdater

    def initialize
        puts "init process"

        puts "configuring updater..."
        file = open('config.json')
        config_json = file.read
        
        configurations = JSON.parse(config_json, symbolize_names: true)
        @artifactory_config = configurations[:artifactory]

        # create url
        @repositories = configurations[:repositories][0]
        oel_url = @repositories[:base_url] + @repositories[:packages][:oel]
        @zip_name = "oel8-#{Date.today.to_time.to_i}.zip"
        @today = Date.today.to_time.to_i
        puts "done.."

        # fetch files
        puts "parsing oracle repository page..."
        parsed_page = parse_url(oel_url + "index.html")
        scraped_links = scrape(parsed_page)
        puts "done.."

        # download and store files
        puts "downloading files..."
        download_rpms(scraped_links, oel_url)
        puts "done..."

        # create virtual repository
        puts "create local repo..."
        repo_name = create_local_repo_artifactory
        puts "done ..."

        puts "uploading files to repo"
        upload_files_to_local_repo
        puts "done ..."

        # copy files from disk to artifactory
        puts "update virtual repo..."
        update_virtual_repo(repo_name)
        puts "done ..."

        puts "delete local files"
        clean_local_files
        puts "done ..."

        puts "process finished"
    end

    private

    def parse_url(url)
        response = HTTParty.get(url)
        Nokogiri::HTML(response.body) unless response.body.nil? || response.body.empty?
    end
    
    def scrape(parsed_page)
        links = parsed_page.xpath("//tr//a")
        parsed_links = links.collect do |link|
            link[:href] + "" if link[:href] =~ /^getPackage/
        end
        parsed_links.compact
    end

    def download_rpms(scraped_links, oel_url)
        local_repo = "oel/#{@today}/" + @repositories[:packages][:oel]
        FileUtils.mkdir_p local_repo

        file_count = 0
        
        # Delete zips if exists
        File.delete(@zip_name) if File.exist?(@zip_name)

        Zip::File.open(@zip_name, Zip::File::CREATE) do |zipfile|
            scraped_links.each do |package_url| 
                download_url = oel_url + package_url 
                file_name = package_url.split("/")

                open(local_repo + file_name[1], 'wb') do |file|
                    file << URI.open(download_url).read
                end

                # Two arguments:
                # - The name of the file as it will appear in the archive
                # - The original file, including the path to find it
                zipfile.add(local_repo + file_name[1],  File.join(local_repo, file_name[1]))
                puts "added: #{local_repo + file_name[1]}"
                file_count += 1
            end
        end
        
        puts "downloaded, created and zipped #{file_count} files ..."
    end

    def create_local_repo_artifactory
        # repository configuration taken from
        # https://www.jfrog.com/confluence/display/JFROG/Repository+Configuration+JSON
        repo_name = "oel8-local-#{@today}"
        puts "creating local repo #{repo_name} ..."
        response = HTTParty.put(@artifactory_config[:base_url] + @artifactory_config[:local_repo] + @today.to_s, 
            body: { rclass: 'local', 
                    description: 'oel8 artifacts',
                    packageType:'rpm'}.to_json, 
            headers: @artifactory_config[:headers]).response
        
        if response.code.eql? "200"
            puts "artifactory response #{response.body.inspect}"
            puts "created local repo..."
            return repo_name
        else
            puts "artifactory response #{response.body.inspect}"
        end
    end

    def upload_files_to_local_repo
        puts "uploading files to local repo"
        local_url = @artifactory_config[:base_url] + @artifactory_config[:upload_url] + @today.to_s 

        #using curl as http party is not able to push binary files
        # we use X-Explode-Archive-Atomic: true to extract the files once in the repo
        Kernel.system "curl -H 'X-JFrog-Art-Api: #{@artifactory_config[:token]}' -X PUT #{local_url} -T #{@zip_name} -H 'Content-Type: application/zip' -H 'X-Explode-Archive-Atomic: true'"
    end

    def update_virtual_repo(new_local_repo_name)
        # Verify if virtual repo exists
        vrepo = HTTParty.get(@artifactory_config[:base_url] + @artifactory_config[:get_repo], query: '?type=virtual', headers: @artifactory_config[:headers]).response.body
        vrepo_json = JSON.parse(vrepo, symbolize_names: true).first

        # we check if virtual repository already exists and we only update the reference to new local 
        if (vrepo_json && vrepo_json[:key].eql?("virtual-oel8-repo") && vrepo_json[:rclass].eql?("virtual"))
            # Update reference to new local repo
            response = HTTParty.put(@artifactory_config[:base_url] + @artifactory_config[:virtual_repo], 
                body: { key: 'virtual-oel8-repo', 
                        rclass: 'virtual', 
                        packageType:'rpm', 
                        repositories: ["#{new_local_repo_name}"], 
                        externalDependenciesEnabled: 'false'}.to_json, 
                headers: @artifactory_config[:headers]).response
            
            if response.code.eql? "200"
                puts "artifactory response #{response.body.inspect}"
                puts "created and updated virtual repo..."
            end
        else
            # Update reference to new local repo
            response = HTTParty.post(@artifactory_config[:base_url] + @artifactory_config[:virtual_repo], 
                body: { repositories: ["#{new_local_repo_name}"]}.to_json, 
                headers: @artifactory_config[:headers]).response
            
            if response.code.eql? "200"
                puts "artifactory response #{response.body.inspect}"
                puts "updated virtual repo..."
            end
        end
    end

    def clean_local_files
        puts "cleaning local files"
        File.delete(@zip_name) if File.exist?(@zip_name)
        FileUtils.remove_dir("oel/")
    end

end

Oelupdater.new