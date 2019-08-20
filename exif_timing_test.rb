require 'exifr/jpeg'
require 'benchmark'

def generate_metadata(source)
    exif = EXIFR::JPEG.new(source)
    metadata = {}
    metadata['camera'] = "#{exif.make} #{exif.model}"
    metadata['datetime'] = exif.date_time
    metadata['iso'] = exif.iso_speed_ratings
    metadata['flash'] = exif.flash
    metadata['aperture'] = exif.aperture_value
    metadata['exposure_bias'] = exif.exposure_bias_value
    metadata['exposure_time'] = exif.exposure_time
    metadata['focal_length'] = exif.focal_length
    metadata['orientation'] = exif.orientation.to_sym.to_s
    metadata
 end

# read the exif data from the original image
def generate_metadata_old(source)
    # run ImageMagick's identify against the image, pulling out the exif tags
    exif_data_raw = `identify -format "%[EXIF:*]" "#{source}"`
    # split the exif data string into a Hash
    exif_data = exif_data_raw.split(/\n/).map { |l| l[5,1000].split(/=/, 2)}.to_h
    
    # pull out the exif data that i'm interested in.
    exif_data['Model'] ||= ""
    metadata = {}
    metadata['camera'] = "#{exif_data['Make']} #{exif_data['Model'].gsub(/^#{exif_data['Make']}\s*/, '')}"
    metadata['datetime'] = exif_data['DateTime']
    metadata['iso'] = exif_data['ISOSpeedRatings']
    metadata['flash'] = exif_data['Flash']
    metadata['aperture'] = exif_data['ApertureValue']
    metadata['exposure_bias'] = exif_data['ExposureBiasValue']
    metadata['exposure_time'] = exif_data['ExposureTime']
    metadata['focal_length'] = exif_data['FocalLength']
    metadata['orientation'] = exif_data['Orientation']
    metadata
end

dir = "test/Atlanta/20040704-fireworks"
timing = {
    :exifr => 0.0,
    :identify => 0.0,
}

Benchmark.bm do |x|
    x.report do
        Dir.new(dir).each do |f|
            if f.end_with?(".JPG") or f.end_with?(".jpg")
                generate_metadata_old("#{dir}/#{f}")
            end
        end    
    end
    x.report do
        Dir.new(dir).each do |f|
            if f.end_with?(".JPG") or f.end_with?(".jpg")
                generate_metadata("#{dir}/#{f}")
            end
        end    
    end
end

#    user     system      total        real
#0.023330   0.044488   0.758305 (  1.041464)
#0.039881   0.002987   0.042868 (  0.043151)
