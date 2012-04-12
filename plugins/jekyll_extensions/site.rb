# encoding: utf-8
#
# Monkey patches hooking into Jekyll::Site core to add category indexes and feeds
#
# Jekyll category page generator.
# http://recursive-design.com/projects/jekyll-plugins/
#
# Version: 0.1.4 (201101061053)
#
# Category generator:
# Copyright (c) 2010 Dave Perrett, http://recursive-design.com/
#
# Audiofeed generator:
# Copyright (c) 2012 Sven Pfleiderer, http://blog.roothausen.de/
#
# Licensed under the MIT license (http://www.opensource.org/licenses/mit-license.php)

module Jekyll

  # The Site class is a built-in Jekyll class with access to global site config information.
  class Site

    attr_accessor :audioformats

    # Reset Site details.
    #
    # Overrides jekyll's reset method to add audio formats
    #
    # Returns nothing
    def reset
      self.time            = if self.config['time']
                               Time.parse(self.config['time'].to_s)
                             else
                               Time.now
                             end
      self.layouts         = {}
      self.posts           = []
      self.pages           = []
      self.static_files    = []
      self.categories      = Hash.new { |hash, key| hash[key] = [] }
      self.audioformats    = Hash.new { |hash, key| hash[key] = [] }
      self.tags            = Hash.new { |hash, key| hash[key] = [] }

      if !self.limit_posts.nil? && self.limit_posts < 1
        raise ArgumentError, "Limit posts must be nil or >= 1"
      end
    end

    # The Hash payload containing site-wide data.
    #
    # Overrides jekyll's site_payload method to put audio formats into render context
    #
    def site_payload
      {"site" => self.config.merge({
        "time"          => self.time,
        "posts"         => self.posts.sort { |a, b| b <=> a },
        "pages"         => self.pages,
        "html_pages"    => self.pages.reject { |page| !page.html? },
        "categories"    => post_attr_hash('categories'),
        "audioformats"  => post_attr_hash('audioformats'),
        "tags"          => post_attr_hash('tags') } ) }
    end


    # Read all the files in <source>/<dir>/_posts and create a new Post
    # object with each one.
    #
    # Overrides jekyll's read_post method to add audio formats
    #
    # dir - The String relative path of the directory to read.
    #
    # Returns nothing.
    def read_posts(dir)
      base = File.join(self.source, dir, '_posts')
      return unless File.exists?(base)
      entries = Dir.chdir(base) { self.filter_entries(Dir['**/*']) }

      # first pass processes, but does not yet render post content
      entries.each do |entry|
        if Post.valid?(entry)
          post = Post.new(self, self.source, dir, entry)

          # Monkeypatch:
          # On preview environment (localhost), publish all posts
          if ENV.has_key?('OCTOPRESS_ENV') && ENV['OCTOPRESS_ENV'] == 'preview' && post.data.has_key?('published') && post.data['published'] == false
            post.published = true
            # Set preview mode flag (if necessary), `rake generate` will check for it
            # to prevent pushing preview posts to productive environment
            File.open(".preview-mode", "w") {}
          end

          if post.published && (self.future || post.date <= self.time)
            self.posts << post
            post.categories.each { |c| self.categories[c] << post }
            post.audioformats.each { |f| self.audioformats[f] << post }
            post.tags.each { |c| self.tags[c] << post }
          end
        end
      end

      self.posts.sort!

      # limit the posts if :limit_posts option is set
      if limit_posts
        limit = self.posts.length < limit_posts ? self.posts.length : limit_posts
        self.posts = self.posts[-limit, limit]
      end
    end

    # Creates an instance of CategoryIndex for each category page, renders it, and
    # writes the output to a file.
    #
    #  +category_dir+ is the String path to the category folder.
    #  +category+     is the category currently being processed.
    def write_category_index(category_dir, category)
      index = CategoryIndex.new(self, self.source, category_dir, category)
      index.render(self.layouts, site_payload)
      index.write(self.dest)
      # Record the fact that this page has been added, otherwise Site::cleanup will remove it.
      self.pages << index

      # Create an Atom-feed for each index.
      feed = CategoryFeed.new(self, self.source, category_dir, category)
      feed.render(self.layouts, site_payload)
      feed.write(self.dest)
      # Record the fact that this page has been added, otherwise Site::cleanup will remove it.
      self.pages << feed
    end

    # Loops through the list of category pages and processes each one.
    def write_category_indexes
      if self.layouts.key? 'category_index'
        dir = self.config['category_dir'] || 'categories'
        self.categories.keys.each do |category|
          self.write_category_index(File.join(dir, category.gsub(/_|\P{Word}/, '-').gsub(/-{2,}/, '-').downcase), category)
        end

        # Throw an exception if the layout couldn't be found.
      else
        throw "No 'category_index' layout found."
      end
    end

    # Creates an instance of AudioFormatFeed for each audio format, renders it, and
    # writes the output to a file.
    #
    #  +audioformat_feed_dir+ is the String path to the audioformat folder.
    #  +audioformat+     is the audioformat currently being processed.
    def write_audioformat_feed(audioformat_feed_dir, audioformat)
      # Create an Atom-feed for each audio format.
      feed = AudioFormatFeed.new(self, self.source, audioformat_feed_dir, audioformat)
      feed.render(self.layouts, site_payload)

      feed.write(self.dest)
      # Record the fact that this feed has been added, otherwise Site::cleanup will remove it.
      self.pages << feed
    end

    def write_audioformat_feeds
      dir = self.config['audioformat_feed_dir'] || 'audioformat_feeds'

      self.audioformats.keys.each do |audioformat|
        self.write_audioformat_feed(File.join(dir, audioformat.gsub(/_|\P{Word}/, '-').gsub(/-{2,}/, '-').downcase), audioformat)
      end
    end

  end

end

