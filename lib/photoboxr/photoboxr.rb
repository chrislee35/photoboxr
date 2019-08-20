require 'fileutils'
require 'erubis'
require 'uri'
require 'json'
#require 'concurrent'
require 'exifr/jpeg'
require 'image_size'
require 'human_size'

# TODO
# Regenerate html documents when the template updates

class Erubis::Eruby
    attr_accessor :mtime
end

# $pool = Concurrent::ThreadPoolExecutor.new(
#     :min_threads => [2, Concurrent.processor_count].max,
#     :max_threads => [2, Concurrent.processor_count].max,
#     :max_queue   => [2, Concurrent.processor_count].max * 5,
#     :fallback_policy => :caller_runs
# )

module PhotoBoxr
    VERSION = "0.0.2"
    
    class Item
        attr_reader :source, :dest, :mtime, :basename, :thumbname, :destname, :metadata
        attr_accessor :comment

        def initialize(source, dest, thumbnail)
            @source = source
            @dest = dest
            @thumbnail = thumbnail
            @mtime = File.stat(@source).mtime
            @basename = File.basename(@source)
            @destname = File.basename(@dest)
            @thumbname = File.basename(@thumbnail)
            @metadata = Hash.new
            @comment = ""
        end
        
        def generate_webpage(template, n, p)
            htmlfile = "#{@dest}.html"
            if not File.exists?(htmlfile) or @mtime > File.stat(htmlfile).mtime or template.mtime > File.stat(htmlfile).mtime
                #$pool.post do
                    generate_metadata
                    context = Erubis::Context.new(:up => 'index.html', :item => @destname, :next => n && n.destname, :prev => p && p.destname, :metadata => @metadata, :version => PhotoBoxr::VERSION)
                    html = template.evaluate(context)
                    File.open(htmlfile,"w") do |of|
                        of.puts(html)
                    end
                    #end
                return true
            end
            false
        end

        def generate_metadata
        end
    end
    
    class Image < Item
        def generate_thumbnail
            if not File.exists?(@thumbnail) or @mtime > File.stat(@thumbnail).mtime
                #$pool.post do
                # the [0] converts just the first frame of a multipage/multiframe image
                    `convert -auto-orient -thumbnail 100x100 "#{@source}[0]" "#{@thumbnail}"`
                    #end
                return true
            end
            false
        end
        
        def generate_dest
            if not File.exists?(@dest) or @mtime > File.stat(@dest).mtime
                if @source[-3..-1] == @dest[-3..-1]
                    `ln "#{@source}" "#{@dest}"`
                else
                    puts "converting #{@source} to #{@dest}"
                    `convert "#{@source}[0]" "#{@dest}"`
                end
                return true
            end
            false
        end
        
        def generate_metadata
            fh = File.new(@source)
            imgsize = ImageSize.new(fh)
            @metadata['format'] = imgsize.format
            @metadata['size'] = HumanSize::Size.human_size(fh.size)
            @metadata['width'] = imgsize.width
            @metadata['height'] = imgsize.height
            
            if imgsize.format == :jpeg
                begin
                    exif = EXIFR::JPEG.new(@source)
                    @metadata['camera'] = "#{exif.make} #{exif.model}"
                    @metadata['datetime'] = exif.date_time
                    @metadata['iso'] = exif.iso_speed_ratings
                    @metadata['flash'] = exif.flash
                    @metadata['aperture'] = exif.aperture_value
                    @metadata['exposure_bias'] = exif.exposure_bias_value
                    @metadata['exposure_time'] = exif.exposure_time
                    @metadata['focal_length'] = exif.focal_length
                    @metadata['orientation'] = exif.orientation ? exif.orientation.to_sym.to_s : nil
                rescue EXIFR::MalformedJPEG => e
                   puts "Skipping Malformed JPEG: #{@source}"
                end
            elsif imgsize.format == :tiff
                begin
                    exif = EXIFR::TIFF.new(@source)
                    @metadata['camera'] = "#{exif.make} #{exif.model}"
                    @metadata['datetime'] = exif.date_time
                    @metadata['iso'] = exif.iso_speed_ratings
                    @metadata['flash'] = exif.flash
                    @metadata['aperture'] = exif.aperture_value
                    @metadata['exposure_bias'] = exif.exposure_bias_value
                    @metadata['exposure_time'] = exif.exposure_time
                    @metadata['focal_length'] = exif.focal_length
                    @metadata['orientation'] = exif.orientation ? exif.orientation.to_sym.to_s : nil
                rescue EXIFR::MalformedTIFF => e
                   puts "Skipping Malformed TIFF: #{@source}" 
                end
            end
         end
        
        # read the exif data from the original image
        def generate_metadata_old
            # run ImageMagick's identify against the image, pulling out the exif tags
            exif_data_raw = `identify -format "%[EXIF:*]" "#{@source}"`
            # split the exif data string into a Hash
            exif_data = exif_data_raw.split(/\n/).map { |l| l[5,1000].split(/=/, 2)}.to_h
            
            # pull out the exif data that i'm interested in.
            exif_data['Model'] ||= ""
            @metadata['camera'] = "#{exif_data['Make']} #{exif_data['Model'].gsub(/^#{exif_data['Make']}\s*/, '')}"
            @metadata['datetime'] = exif_data['DateTime']
            @metadata['iso'] = exif_data['ISOSpeedRatings']
            @metadata['flash'] = exif_data['Flash']
            @metadata['aperture'] = exif_data['ApertureValue']
            @metadata['exposure_bias'] = exif_data['ExposureBiasValue']
            @metadata['exposure_time'] = exif_data['ExposureTime']
            @metadata['focal_length'] = exif_data['FocalLength']
            @metadata['orientation'] = exif_data['Orientation']
        end
    end
    
    class Video < Item
        def generate_thumbnail
            if not File.exists?(@thumbnail) or File.stat(@source).mtime > File.stat(@thumbnail).mtime
                #$pool.post do
                    `ffmpeg -i "#{@source}" -vcodec mjpeg -vframes 1 -an -f rawvideo -s 100x100 "#{@thumbnail}"`
                    #end
                return true
            end
            false
        end

        def generate_dest
            if not File.exists?(@dest) or File.stat(@source).mtime > File.stat(@dest).mtime
                # (mov|avi|flv|mp4|m4v|mpeg|mpg|webm|ogg)
                if @dest =~ /\.webm$/i
                    `ffmpeg -i "#{@source}" -vcodec libvpx -acodec libvorbis -qmax 25 "#{@dest}"`
                elsif @dest =~ /\.mp4/i
                    `ffmpeg -i "#{@source}" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k -movflags +faststart -vf scale=-2:720,format=yuv420p "#{@dest}"`
                elsif @dest =~ /\.ogg/i
                    # i'll figure this out later
                end
                return true
            end
            false
        end
        
        def generate_metadata
            ffprobe_json_raw = `ffprobe -v error -show_format -show_streams -of json "#{@source}"`
            @metadata = JSON.parse(ffprobe_json_raw)
            if @metadata['format'] == nil
                @metadata = { 'format' => {'format_long_name' => 'unknown', 'duration' => 'unknown', 'size' => 'unknown' }, 'streams' => [] }
            end
        end
    end
    
    class Note < Item
        def generate_thumbnail
            false
        end
        
        def generate_dest
            if not File.exists?(@dest) or File.stat(@source).mtime > File.stat(@dest).mtime
                `cp "#{@source}" "#{@dest}"`
                return true
            end
            false
        end
        
        def generate_metadata
            @metadata['magic'] = `file "#{@source}"`.split(": ")[1]
            @metadata['stat'] = File.stat(@source)
        end
    end        
    
    class Directory
        attr_reader :rel, :image, :basename, :itemcount
        # set up a data structure to capture statistics
        @@stats = {
            'time' => {
                'enumerate' => 0.0,
                'generate' => 0.0,
            },
            'total' => {
                'folder' => 1, # for the inputroot
                'image' => 0,
                'video' => 0,
                'note' => 0,
                'thumbnail' => 0,
                'resource' => 0
            },
            'generated' => {
                'folder' => 0,
                'image' => 0,
                'video' => 0,
                'note' => 0,
                'thumbnail' => 0,
                'resource' => 0,
                'dest' => 0
            }
        }
        @@config = {
            'process_photos' => true,
            'process_videos' => true,
            'process_notes' => true,
            'print_item' => false,
            'print_directory' => false,
            'output_video_format' => 'mp4',
        }

        def initialize(inputroot, outputroot, fullpath)
            @inputroot = inputroot
            @outputroot = outputroot
            @basename = File.basename(fullpath)
            @dir = fullpath # location in filesystem of input
            @rel = fullpath[inputroot.length + 1, fullpath.length] # relative path for HTML output
            @rel ||= ""
            @out = outputroot + "/" + @rel # location in filesystem of output
            
            # set up arrays to track subdirectories, images, videos, and notes in this folder
            # enumerate will fill these in.
            @subdirs = []
            @images = []
            @videos = []
            @notes = []
            
            # enumerate all the subdirs, images, videos, and notes in the folder
            enumerate
            # select the icon image for this folder
            select_folder_image
            @itemcount = @subdirs.length + @images.length + @videos.length + @notes.length
        end
        
        def self.set_config(key, value)
            @@config[key] = value
        end
        
        def set_config(key, value)
            @@config[key] = value
        end
        
        def _parse_comments(filename)
            comments = Hash.new
            prevkey = nil
            File.new("#{@dir}/comments.properties").each_line do |l|
                l = l.chomp
                newline = false
                if l =~ /\\$/
                    newline = true
                    l = l.gsub(/\\$/, "\n")
                end
                
                if prevkey
                    comments[prevkey] += l
                    if !newline
                        prevkey = nil
                    end
                else
                    key, comment = l.split(/=/, 2)
                    comments[key] = comment
                    if newline
                        prevkey = key
                    end
                end
            end
            comments
        end
        
        def enumerate
            starttime = Time.now
            # check for comments
            comments = Hash.new
            if File.exist?("#{@dir}/comments.properties")
                begin
                    comments = _parse_comments("#{@dir}/comments.properties")
                rescue Exception => e
                    puts e
                    puts e.backtrace.join("\n")
                    raise "Could not process #{@dir}/comments.properties"
                end
            end
            # check for excludes
            exclude = Hash.new
            if File.exist?("#{@dir}/albumfiles.txt")
                exclude = File.new("#{@dir}/albumfiles.txt").read.split(/\n/).find_all {|l| l.start_with?("-")}.map {|l| [l.split(/\t/)[0], true]}.to_h
            end
            # for each item, choose to add it to subdirs, images, videos, or to ignore it
            Dir.new(@dir).each do |f|
                if f =~ /^\./ or exclude[f] or f =~ /albumfiles\.txt/
                    next
                end
                videore = /\.(mov|avi|flv|mp4|m4v|mpeg|mpg|webm|ogg)$/i
                if File.directory?("#{@dir}/#{f}")
                    @@stats['total']['folder'] += 1
                    newdir = Directory.new(@inputroot, @outputroot, "#{@dir}/#{f}")
                    if newdir.itemcount > 0
                        @subdirs << newdir
                    end
                elsif f =~ /\.(jpg|gif|jpeg|png|tif|tiff|svg|bmp)$/i and @@config['process_photos'] 
                    @@stats['total']['image'] += 1
                    imgname = "#{@outputroot}/#{@rel}/#{f}"
                    thumbname = "#{@outputroot}/#{@rel}/thumb/#{f}"
                    # convert non-thumbable formats to jpg
                    if f =~ /\.(tiff|svg|bmp)$/i
                        thumbname = "#{@outputroot}/#{@rel}/thumb/#{f}.jpg"
                        puts "thumbname #{f} -> #{thumbname}"
                    end
                    # convert non-web-viewable formats to jpg
                    if f =~ /\.(tiff|bmp)$/i
                        imgname = "#{@outputroot}/#{@rel}/#{f}.jpg"
                        puts "imgname #{f} -> #{imgname}"
                    end
                    @images << Image.new("#{@dir}/#{f}", imgname, thumbname)
                    if comments[f]
                        @images.last.comment = comments[f]
                    end
                elsif f =~ videore and @@config['process_videos']
                    @@stats['total']['video'] += 1
                    filename = f.gsub(videore, '.'+@@config['output_video_format'])
                    thumbnail = f.gsub(videore, '.jpg')
                    @videos << Video.new("#{@dir}/#{f}", "#{@outputroot}/#{@rel}/#{filename}", "#{@outputroot}/#{@rel}/thumb/#{thumbnail}")
                    if comments[f]
                        @videos.last.comment = comments[f]
                    end
                elsif f =~ /\.(txt|rtf|doc|docx|pdf)$/i and @@config['process_notes'] 
                    @@stats['total']['note'] += 1
                    @notes << Note.new("#{@dir}/#{f}", "#{@outputroot}/#{@rel}/#{f}", "#{@outputroot}/#{@rel}/thumb/#{f}")
                    if comments[f]
                        @notes.last.comment = comments[f]
                    end
                else
                    puts "ignoring #{dir}/#{f}" if $debug;
                end
                @subdirs.sort! { |a,b| a.basename <=> b.basename }
                @images.sort! { |a,b| a.mtime <=> b.mtime }
                @videos.sort! { |a,b| a.mtime <=> b.mtime }
                @notes.sort! { |a,b| a.mtime <=> b.mtime }
            end
            @@stats['time']['enumerate'] = Time.now - starttime
        end
        
        def select_folder_image
            #puts "select_folder_image for #{@dir}"
            @image = "res/album.png"
            # next, let's find the icon image for this folder
            # do I have one defined by configuration?
            if File.exist?("#{@dir}/meta.properties")
                properties = File.open("#{@dir}/meta.properties").read
                if properties =~ /folderIcon=(.*)/m
                    thumbnail = $1.strip
                    if thumbnail.downcase.end_with?('.jpg')
                        @image = "thumb/#{thumbnail}"
                        return @image
                    else
                        @subdirs.each do |subdir|
                            #puts "#{subdir.basename} #{thumbnail} -> #{subdir.image}"
                            if subdir.image and subdir.basename == thumbnail
                                @image = subdir.basename+"/"+subdir.image
                                return @image
                            end
                        end
                    end
                end
            end
            if @images.length > 0
                # do I have any images?    If so, I'll pick the first one. (it's gotta be the best one, right?)
                @image = "thumb/"+@images[0].thumbname
            elsif @videos.length > 0
                # do I have any videos?
                @image = "thumb/"+@videos[0].thumbname
            else
                # ok, let's go through my subdirs and see if any of them have an image to use
                @subdirs.each do |subdir|
                    if subdir.image
                        @image = subdir.basename+"/"+subdir.image
                        break
                    end
                end
            end
            @image
        end

        def generate(templates)
            puts("Generating directory #{@dir}") if @@config['print_directory']
            starttime = Time.now
            # let's first check if the output directory exists (added thumb to make sure it's created too)
            if not File.exist?("#{@out}/thumb")
                # we need to create the directory
                FileUtils.mkdir_p("#{@out}/thumb")
            end
            # next, let's check if the resources are all copied over, first create the res dir
            if not File.exists?("#{@out}/res")
                # we need to create the res folder
                FileUtils.mkdir_p("#{@out}/res")
            end
            # for each resource, copy it over if it's newer
            Dir.new(templates['res']).each do |item|
                next if item == '..' or item == '.'
                @@stats['total']['resource'] += 1
                if not File.exists?("#{@out}/res/#{item}") or File.stat("#{templates['res']}/#{item}").mtime > File.stat("#{@out}/res/#{item}").mtime
                    @@stats['generated']['resource'] += 1
                    `cp "#{templates['res']}/#{item}" "#{@out}/res/#{item}"`
                end
            end
            # if the index.html is missing or if it's older than the source directory
            # BUG: this fails to find new folders after generation.
            if not File.exist?("#{@out}/index.html") or File.stat(@dir).mtime > File.stat("#{@out}/index.html").mtime
                @@stats['generated']['folder'] += 1
                # then we need to (re)create the index.html
                context = Erubis::Context.new(:item => @rel, :subdirs => @subdirs, :images => @images, :videos => @videos, :notes => @notes, :version => PhotoBoxr::VERSION)
                html = templates['folder'].evaluate(context)
                #puts html
                File.open("#{@out}/index.html", "w") do |of|
                    of.puts(html)
                end
            end
                        
            _generate_items(templates, 'image', @images)
            _generate_items(templates, 'video', @videos)
            _generate_items(templates, 'note', @notes)

            @subdirs.each do |subdir|
                subdir.generate(templates)
            end
            #$pool.shutdown
            #$pool.wait_for_termination
            @@stats['time']['generate'] = Time.now - starttime
        end

        def _generate_items(templates, type, items)
            template = templates[type]
            0.upto(items.length - 1) do |i|
                item = items[i]
                puts("Generating item #{item}") if @@config['print_items']
                prev = nextf = nil
                prev = items[i-1] if i > 0
                nextf = items[i+1] if i < items.length - 1
                @@stats['total'][type] += 1
                if item.generate_webpage(template, nextf, prev)
                    @@stats['generated'][type] += 1
                end
                @@stats['total']['thumbnail'] += 1
                if item.generate_thumbnail
                    @@stats['generated']['thumbnail'] += 1
                end
                if item.generate_dest
                    @@stats['generated']['dest'] += 1
                end
            end
        end
        
        def print_stats
            puts "**    PhotoBoxr Statistics     **"
            printf("Enumeration time: %0.2f seconds\n", @@stats['time']['enumerate'])
            printf(" Generation time: %0.2f seconds\n", @@stats['time']['generate'])
            puts
            puts "            Type Evaluated Generated"
            puts "========== ========= ========="
            ['folder','image','video','note','thumbnail','resource'].each do |type|
                printf("%#9ss %#9d %#9d\n", type, @@stats['total'][type] || 0, @@stats['generated'][type])
            end
        end
    end
    
    class TemplateManager
        def self.get_templates(scheme_name)
            basedir = File.dirname(File.dirname(File.dirname(__FILE__)))
            if File.exist?("#{basedir}/templates/#{scheme_name}")
                templates = {}
                ['folder', 'image', 'video', 'note'].each do |x|
                    filename = "#{basedir}/templates/#{scheme_name}/#{x}.html"
                    templates[x] = Erubis::Eruby.new(File.open(filename).read)
                    templates[x].mtime = File.stat(filename).mtime
                end
                templates['res'] = "#{basedir}/templates/#{scheme_name}/res"
                return templates
            end
        end
    end
end

if __FILE__ == $0
    PhotoBoxr::Directory.set_config('process_videos', false)
    d = PhotoBoxr::Directory.new("test/AJCF", "test/html", "test/AJCF")
    templates = PhotoBoxr::TemplateManager.get_templates('boring')
    d.generate(templates)
    d.print_stats
end