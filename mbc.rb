#! /usr/bin/env ruby 

# TODO: make sizes cmd-line option
# delta should be ms resolution

def get_duration(fn)
  line = `ffmpeg -y -i #{fn} -vframes 1 -s 2x2 -ss 00:00:00 -an -vcodec png -f rawvideo /dev/null 2>&1`.split(/\n/).grep(/Duration/).first
  # "  Duration: 02:20:01.2, start: 0.000000, bitrate: 699 kb/s"
  time = /^\s+Duration:\s+([\d:\.]+)/.match(line)[1]
  # "02:20:01.2"
  h, m, s, ms = /^(\d+):(\d+):(\d+)\.(\d+)$/.match(time)[1..4].map{|v| v.to_i}
  seconds = h * 60 * 60 + m * 60 + s
end

$first = true
#$ysize= 1440
#$collector = "collect.png"

$b64d=('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a + ["+", "/"]

def b64(i, w) 
  s= ""
  v = i
  begin
    s += $b64d[v % 64]
    v /= 64
  end while v > 0
  raise "Value is too large for b64 with #{w} chars!" if s.length > w
  s += "." * (w - s.length) if s.length < w
  s
end

class XPM
  attr_reader :columns, :rows, :colors, :chars_per_pixel, 
      :pixel_to_color, :color_to_pixel, :pixel_data, :filename
  def initialize
  end

  def create(columns, rows, chars_per_pixel) 
    @columns = columns
    @rows = rows
    @colors = 0
    @color_counter = 0
    @chars_per_pixel = chars_per_pixel
    @pixel_to_color = {}
    @color_to_pixel = {}
    @current_x = 0

    black = pixel_for_color("#000000")
    @pixel_data = Array.new(rows) { Array.new(columns, black) }
    self
  end

  def read(fn)
    @filename = fn
    raw = File.read(@filename)
    cmd = "[" + raw.gsub(/^\/\*[^\n]+\n/, "").sub(/\A.*\{/, "").
        sub(/\};\n\Z/, "").gsub(/#/, "\\#") + "]"
    data = eval(cmd)
    @columns, @rows, @colors, @chars_per_pixel = data[0].split(/\s+/).map{|v| v.to_i}
    cd = data[1..@colors].map {|v| /^(.+) c (?:(#\w+)|(\w+))/.match(v)[1,2] }
    @pixel_to_color = cd.inject({}) {|h,v| h[v[0]] = v[1]; h }
    @color_to_pixel = cd.inject({}) {|h,v| h[v[1]] = v[0]; h }
    @pixel_data = data[@colors+1..data.size].map{|row_s| 
        row_s.unpack("a#{@chars_per_pixel}" * @columns) }
    self
  end

  def median_color
    color_stat = {}
    rows.times {|y|
      columns.times {|x|
        color = pixel_to_color[pixel_data[y][x]]
        color_stat[color] ||= 0
        color_stat[color] += 1
      }
    }
    sorted = color_stat.to_a.sort {|a,b| a[1] <=> b[1]}
    sorted[sorted.size / 2][0]
  end

  def pixel_for_color(c)
    return color_to_pixel[c] if color_to_pixel[c]
    pixel = ""
    begin 
      @color_counter += 1
      pixel = b64(@color_counter, @chars_per_pixel)
    end while pixel_to_color[pixel]
    @colors += 1
    pixel_to_color[pixel] = c
    color_to_pixel[c] = pixel
    pixel
  end

  def add_bar_with_color(c)
    return if @current_x > @columns - 1
    #raise "#{@current_x} larger than columns #{columns}" if @current_x > @columns - 1
    cv = pixel_for_color(c)
    rows.times {|y| pixel_data[y][@current_x] = cv }
    @current_x += 1
    self
  end

  def values_as_s
    "#{columns} #{rows} #{colors} #{chars_per_pixel} "
  end

  def colors_as_s
    a = []
    pixel_to_color.keys.sort.each {|pixel|
      color = pixel_to_color[pixel]
      s = "#{pixel} c #{color}"
      a.push(s)
    }
    a.inspect.sub(/\A\[/, "").sub(/\]\Z/, "").gsub(/", "/, "\",\n\"") + ","
  end

  def pixels_as_s 
    a = []
    rows.times{|y| 
      s = ""
      columns.times{|x|
        s += pixel_data[y][x]
      }
      a.push(s)
    }
    a.inspect.sub(/\A\[/, "").sub(/\]\Z/, "").gsub(/", "/, "\",\n\"")
  end

  def save(fn)
    @filename = fn
    raw = <<EOX
/* XPM */
static char *#{File.basename(fn, ".xpm")}[] = {
/* columns rows colors chars-per-pixel */
#{values_as_s.inspect},
#{colors_as_s}
/* pixels */
#{pixels_as_s}
};
EOX
    File.open(filename, "w") {|f| f.write(raw)}
  end

end

def take_ss_at(fn, s, out_fn_prefix)
  silent = $first ? "" : ">/dev/null 2>&1 "
  cmd="ffmpeg -ss #{s} -y -i #{fn} -vframes 1 -an -vcodec " + 
    "png -f rawvideo #{out_fn_prefix}.png"
  puts cmd if $first 
  system "#{cmd} #{silent}"
  $first = false
  system "convert #{out_fn_prefix}.png #{out_fn_prefix}.xpm"
  $collector.add_bar_with_color(XPM.new.read("#{out_fn_prefix}.xpm").median_color)
end

def help
  puts "USAGE: $0 <filename> <x size> <y size> <barcode file>"
  exit
end

def create_barcode
  #system "rm -f #{$collector}"
  
  $file = ARGV.shift || help
  $xsize = (ARGV.shift || help).to_i
  $ysize = (ARGV.shift || help).to_i
  $barcode_file = ARGV.shift || help
  
  duration=get_duration($file)
  #$xsize = 2560
  #$xsize = 25
  
  delta=duration/$xsize.to_f
  #def create(columns, rows, chars_per_pixel) 
  $collector = XPM.new.create($xsize, $ysize, 2)
  
  s = 0.0
  c = 0
  while s < duration
    puts "#{c} of #{$xsize}"
    #fn = "ss.png"
    #fn_prefix = "ss#{c}"
    fn_prefix = "ss"
    out_fn = "ss.png"
    take_ss_at($file, s.to_i, fn_prefix)
    if File.exists?(out_fn) && File.stat(out_fn).size > 0
      c += 1
    else
      puts "empty, skipped"
    end
    #exit if c > 10
    s += delta
  end
  $collector.save("collect.xpm")
  system "convert collect.xpm #{$barcode_file}"
end

create_barcode if ARGV.size > 0 
