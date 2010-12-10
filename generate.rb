require 'nokogiri'
require 'fileutils'
require 'osx/plist'

class Nokogiri::XML::Document
  def remove_empty_lines!
    self.xpath("//text()").each { |text| text.remove unless text.content.to_s.match(/[^\n\s]/m) }; self
  end
end

generate_2x = ARGV.include?("--generate-2x")
generate_svg = !ARGV.include?("--no-generate-svg")
generate_png = !ARGV.include?("--no-generate-png")
trim_png = !ARGV.include?("--no-trim")

max_scale = generate_2x ? 2 : 1

FileUtils.mkdir_p(%w{png svg trim}.map{|subdir| File.join("countries", subdir)})

WORLD_SVG_FILENAME = 'resources/BlankMap-World6-Equirectangular.svg'
COUNTRY_TABLE_FILENAME = 'resources/iso_country_table.html'

if generate_svg
  @countries = []

  country_html = open(COUNTRY_TABLE_FILENAME) { |f| Nokogiri::HTML(f) }
  country_html.css('tr td:nth-child(2)').each do |cell|
    content = cell.content.strip
    next unless content.match(/^[a-zA-Z]{2}$/)
    @countries << cell.content.strip
  end

  @countries.uniq!

  world_svg = open(WORLD_SVG_FILENAME) { |f| Nokogiri::XML(f) }

  base_svg = world_svg.dup(1)
  base_svg.search("*//path", "*//g").each do |geom|
    geom.remove
  end
  base_svg.remove_empty_lines!

  base_file = File.open("base.xml", "w")
  base_svg.write_to(base_file)
  base_file.close

  countries_file = File.open("countries/countries.txt", "w")

  @countries.each do |country|
    country.downcase!
    geometry = world_svg.search("//*[@id='#{country}']").first
    puts "#{country} - #{geometry ? 'OK' : 'NOT FOUND'}"
  
    next unless geometry
  
    countries_file.write(country + "\n")
  
    base_file = File.open("base.xml")
    new_svg = Nokogiri::XML(base_file)
  
    base_file.close
  
    (new_svg/"style").first.add_next_sibling(geometry)
    added_geometry = (new_svg/"*[@id='#{country}']").first
    added_geometry.default_namespace = new_svg.root.namespace
  
    svg_file = File.open("countries/svg/#{country}.svg", "w")
    new_svg.write_to(svg_file)
    svg_file.close
  end

  countries_file.close

  FileUtils.remove("base.xml")
end

if generate_png
  puts "Generating PNG files from SVG files..."
  (1..max_scale).each do |scale|
    density = 72 * scale
    suffix = scale == 1 ? "" : "@2x"
    Dir.glob("countries/svg/*").each do |svg|
      base_name = File.basename(svg, ".svg")
      `convert +antialias -density #{density} -background none #{svg} countries/png/#{base_name}#{suffix}.png`
    end
  end
end

if trim_png
  puts "Trimming PNG files..."
  dict = Hash.new { |hash, key| hash[key] = {} }
  Dir.glob("countries/png/*").each do |png|
    file_name = File.basename(png)
    base_name = file_name.match(/([a-z]{2})(@2x)?/)[1]
    scale = file_name.match(/@2x/) ? 2 : 1
    dict[base_name][scale.to_s] = `convert #{png} -trim -format "{{%X,%Y},{%w,%h}}" -write info:- countries/trim/#{file_name}`.strip
  end
  info_plist = File.open("countries/countries_geometry.plist", "w")
  OSX::PropertyList.dump(info_plist, dict)
  info_plist.close
end