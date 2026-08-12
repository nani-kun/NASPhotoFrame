#!/usr/bin/env ruby
# Builds the compact city table bundled by NASPhotoFrame from GeoNames'
# cities15000.txt and admin1CodesASCII.txt exports. Usage:
#   ruby scripts/build_geonames_cities_db.rb cities15000.txt admin1CodesASCII.txt > cities.tsv

input_path = ARGV.fetch(0)
admin1_path = ARGV.fetch(1)

admin1_names = {}
File.foreach(admin1_path, encoding: "UTF-8") do |line|
  code, name = line.chomp.split("\t", 3)
  admin1_names[code] = name if code && name
end

# The app UI is Chinese. GeoNames' compact admin1 export only carries English
# display names, so localize mainland China's first-level divisions here. Other
# regions retain GeoNames' native/English name instead of losing the level.
admin1_names.merge!({
  "CN.01" => "安徽省", "CN.02" => "浙江省", "CN.03" => "江西省",
  "CN.04" => "江苏省", "CN.05" => "吉林省", "CN.06" => "青海省",
  "CN.07" => "福建省", "CN.08" => "黑龙江省", "CN.09" => "河南省",
  "CN.10" => "河北省", "CN.11" => "湖南省", "CN.12" => "湖北省",
  "CN.13" => "新疆维吾尔自治区", "CN.14" => "西藏自治区",
  "CN.15" => "甘肃省", "CN.16" => "广西壮族自治区",
  "CN.18" => "贵州省", "CN.19" => "辽宁省", "CN.20" => "内蒙古自治区",
  "CN.21" => "宁夏回族自治区", "CN.22" => "北京市", "CN.23" => "上海市",
  "CN.24" => "山西省", "CN.25" => "山东省", "CN.26" => "陕西省",
  "CN.28" => "天津市", "CN.29" => "云南省", "CN.30" => "广东省",
  "CN.31" => "海南省", "CN.32" => "四川省", "CN.33" => "重庆市"
})

File.foreach(input_path, encoding: "UTF-8") do |line|
  fields = line.chomp.split("\t", -1)
  next if fields.length < 9

  geoname_id = fields[0]
  canonical_name = fields[1]
  alternate_names = fields[3].split(",")
  latitude = fields[4]
  longitude = fields[5]
  country_code = fields[8]
  admin1_code = fields[10]
  admin1_name = admin1_names[[country_code, admin1_code].join(".")] || ""

  # Prefer a wholly Han-script alternate name when present. This gives the
  # Chinese UI localized names without bundling the much larger alternate-name
  # table; otherwise retain GeoNames' canonical local name.
  localized_name = alternate_names.find { |name| name.match?(/\A[\p{Han}\s·・]+\z/) }
  name = localized_name || canonical_name
  name = name.tr("\t\r\n", " ")
  admin1_name = admin1_name.tr("\t\r\n", " ")
  puts [geoname_id, name, latitude, longitude, country_code, admin1_name].join("\t")
end
