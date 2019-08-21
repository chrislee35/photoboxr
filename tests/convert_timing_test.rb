require 'RMagick'
include Magick
require 'benchmark'

def subshell(source, thumbnail)
    `convert -auto-orient -thumbnail 100x100 "#{source}[0]" "#{thumbnail}"`
end

# read the exif data from the original image
def rmagick_fill(source, thumbnail)
    thumb = ImageList.new(source).resize_to_fill(100, 100)
    thumb.write(thumbnail)
end

# read the exif data from the original image
def rmagick_fit(source, thumbnail)
    thumb = ImageList.new(source).resize_to_fit(100, 100)
    thumb.write(thumbnail)
end

# read the exif data from the original image
def rmagick_fill(source, thumbnail)
    thumb = ImageList.new(source).resize_to_fill(100, 100)
    thumb.write(thumbnail)
end

dir = "test/Atlanta/20040704-fireworks"
Benchmark.bm do |x|
    x.report("sub:") do
        Dir.new(dir).each do |f|
            if f.end_with?(".JPG") or f.end_with?(".jpg")
                subshell("#{dir}/#{f}", "test3/sub/#{f}")
            end
        end 
    end
    x.report("fill:") do
        Dir.new(dir).each do |f|
            if f.end_with?(".JPG") or f.end_with?(".jpg")
                rmagick_fill("#{dir}/#{f}", "test3/fill/#{f}")
            end
        end
    end
    x.report("fit:") do
        Dir.new(dir).each do |f|
            if f.end_with?(".JPG") or f.end_with?(".jpg")
                rmagick_fit("#{dir}/#{f}", "test3/fit/#{f}")
            end
        end
    end
end

