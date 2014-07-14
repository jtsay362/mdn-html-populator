require 'mechanize'
require 'uri'
require 'net/http'

BASE_URL = 'https://developer.mozilla.org/en-US/docs/Web/HTML/Element'
DOWNLOAD_DIR = './downloaded'

class HtmlTagPopulator

  def initialize(output_path)
    @output_path = output_path
  end

  def download
    puts "Starting download ..."

    FileUtils.mkpath(DOWNLOAD_DIR)

    agent = Mechanize.new
    page = agent.get("#{BASE_URL}")

    page.search('.index li a').each do |a|
      tag_name = a.text().strip
      # Strip <>
      tag_name = tag_name.slice(1, tag_name.length - 2)

      puts "Downloading page for <#{tag_name}> ..."
      uri = URI.parse("#{BASE_URL}/#{tag_name}")
      response = Net::HTTP.get_response(uri)

      puts "Done downloading page for <#{tag_name}>, sleeping ..."
      sleep(1)

      File.write("#{DOWNLOAD_DIR}/#{tag_name}.html", response.body)
    end

    puts "Done downloading!"
  end

  def populate
    @first_document = true

    num_tags_found = 0

    File.open(@output_path, 'w:UTF-8') do |out|
      out.write <<-eos
{
  "metadata" : {
    "mapping" : {
      "_all" : {
        "enabled" : false
      },
      "properties" : {
        "name" : {
          "type" : string",
          "index" : "not_analyzed"
        },
        "summary" : {
          "type" : string",
          "index" : "analyzed"
        }
      }
    }
  },
  "updates" : [
    eos

      Dir["#{DOWNLOAD_DIR}/*.html"].each do |file_path|

        parse_file(file_path, out)
        num_tags_found += 1
      end

      out.write("\n  ]\n}")
    end

    puts "Found #{num_tags_found} tags."
  end

  private

  def parse_file(file_path, out)
    simple_filename = File.basename(file_path)
    tag_name = simple_filename.slice(0, simple_filename.length - 5)

    puts "Parsing file '#{file_path}' for tag <#{tag_name}> ..."

    File.open(file_path) do |f|
      doc = Nokogiri::HTML(f)

      summary = nil
      summary_header = doc.css('#Summary').first
      if summary_header
        summary = summary_header.next_element().text()
      else
        puts "Can't find summary header for tag <#{tag_name}>!"
      end

      doc = {
        name: tag_name,
        summary: summary
      }

      if @first_document
        @first_document = false
      else
        out.write(",\n")
      end

      json_doc = doc.to_json
      out.write(json_doc)
    end

    puts "Done parsing file for tag <#{tag_name}>."
  end

end

output_filename = 'html_tags.json'

download = false

ARGV.each do |arg|
  if arg == '-d'
    download = true
  else
    output_filename = arg
  end
end

populator = HtmlTagPopulator.new(output_filename)

if download
  populator.download()
end

populator.populate()
system("bzip2 -kf #{output_filename}")