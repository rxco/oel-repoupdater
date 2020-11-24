# Oelupdater
# frozen_string_literal: true
require 'httparty'
require 'json'
require 'nokogiri'
require 'open-uri'

require 'pry'

class Oelupdater

    def initialize
        file = open('config.json')
        config_json = file.read
        
        configurations = JSON.parse(config_json, symbolize_names: true)

        # make url
        repositories = configurations[:repositories][0]
        oel_url = repositories[:base_url] + repositories[:packages][:oel]
        
        # fetch files
        parsed_page = parse_url(oel_url + "index.html")
        scraped_links = scrape(parsed_page)
        
        # download and store files
        local_repo = "oel/#{Date.today.to_time.to_i}/" + repositories[:packages][:oel]
        FileUtils.mkdir_p local_repo

        scraped_links.each do |package_url| 
            download_url = oel_url + package_url 
            file_name = package_url.split("/")

            open(local_repo + file_name[1], 'wb') do |file|
                file << URI.open(download_url).read
            end
            break;
        end

        # create virtual repository
        

    end

    private

    def parse_url(url)
        response = HTTParty.get(url)
        Nokogiri::HTML(response) unless response.body.nil? || response.body.empty?
    end
    
    def scrape(parsed_page)
        links = parsed_page.xpath("//tr//a")
        parsed_links = links.collect do |link|
            link[:href] + "" if link[:href] =~ /^getPackage/
        end
        parsed_links.compact
    end

    def create_virtual_repo_artifactory(repo_name)

    end

end

Oelupdater.new