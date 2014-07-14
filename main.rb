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
          "type" : "string",
          "index" : "not_analyzed"
        },
        "summary" : {
          "type" : "string",
          "index" : "no"
        },
        "html5Only" : {
          "type" : "boolean",
          "index" : "no"
        },
        "attributes" : {
          "properties" : {
            "name" : {
              "type" : "string",
              "index" : "not_analyzed"
            },
            "summary" : {
              "type" : "string",
              "index" : "no"
            },
            "html5Only" : {
              "type" : "boolean",
              "index" : "no"
            }
          }
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

      attributes = parse_attributes(doc, tag_name)

      overhead_indicator = doc.css('.overheadIndicator.htmlVer').first

      html5_only = false

      if overhead_indicator && /Introduced[[:space:]]+in[[:space:]]+HTML5/i.match(overhead_indicator.text)
        html5_only = true
      end

      output_doc = {
        name: tag_name,
        summary: summary,
        attributes: attributes,
        html5Only: html5_only
      }

      if @first_document
        @first_document = false
      else
        out.write(",\n")
      end

      json_doc = output_doc.to_json
      out.write(json_doc)
    end

    puts "Done parsing file for tag <#{tag_name}>."
  end

  def parse_attributes(doc, tag_name)
    attributes_header = doc.css('#Attributes').first

    unless attributes_header
      puts "Can't find attributes header for <#{tag_name}>!"
      return []
    end

    element = attributes_header

    until element.nil? || (element.name == 'dl')
      element = element.next_element
    end

    unless element
      puts "Can't find <dl> after attributes header!"
      return []
    end

    attributes = []
    element.css('>dt').each do |dt|
      puts "Got dt for <#{tag_name}>"

      attribute_name_element = dt.css('strong').first

      unless attribute_name_element
        puts "No attribute name found"
        next
      end

      name = attribute_name_element.text().strip

      puts "Found attribute named #{name} for <#{tag_name}>."

      dd = dt.next_element
      summary = dd.text().strip

      html5_only = false

      htmlVersionIndicator = dt.css('.htmlVer').first

      if htmlVersionIndicator && (htmlVersionIndicator.text().strip.downcase == 'html5')
        html5_only = true
      end

      attributes <<  {
        name: name,
        summary: summary,
        html5Only: html5_only
      }
    end

    attributes
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