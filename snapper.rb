require 'optparse'
require 'ostruct'
framework 'Webkit'

module Snapper
  class CLI
    def self.run
      options = OpenStruct.new
      options.agent = 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_2; en-us) ' + 
                      'AppleWebKit/531.21.8 (KHTML, like Gecko) Version/4.0.4 Safari/531.21.10'
      
      opts = OptionParser.new do |opts|
        opts.banner = "Usage: #$0 [options] URL FILE"
        opts.separator ""
        opts.separator "Specific options:"

        opts.on "--height HEIGHT", Integer, "Force snapshot to the given height" do |height|
          options.height = height
        end

        opts.on "--width WIDTH", Integer, "Force snapshot to the given width" do |width|
          options.width = width
        end

        opts.on "--timeout SECONDS", Integer, "Stop loading page after given number of seconds" do |seconds|
          options.timeout = seconds
        end
        
        opts.on "--filetype FILETYPE", String, "Force given output type" do |filetype|
          options.filetype = filetype.to_sym
        end
      end.parse!

      options.url = ARGV.shift
      options.file = ARGV.shift
      
      options.filetype ||= File.extname(options.file).gsub(".", "").to_sym
      
      Application.new(options).run
    end
  end
  
  class Application
    BITMAP_TYPES = { 
      :gif => NSGIFFileType, 
      :jpg => NSJPEGFileType, 
      :png => NSPNGFileType
    }
    
    AVAILABLE_TYPES = BITMAP_TYPES.keys + [:pdf]
    
    attr_accessor :config
    
    def initialize(configuration = Configuration.new)
      self.config = configuration
      NSApplication.sharedApplication.delegate = self
      @view = BrowserView.new(self)
    end
    
    def run
      @view.fetch(config.url)     
      while !timed_out?
        NSRunLoop.currentRunLoop.runUntilDate NSDate.date
      end
      puts "Request timed out.  Attempting to save page anyway...."
      @view.save_as config.file, config.filetype
    end
    
    def webView(view, didFinishLoadForFrame:frame)
      @view.save_as config.file, config.filetype
      NSApplication.sharedApplication.terminate nil
    end
    
    def webView(view, didFailLoadWithError:error, forFrame:frame)
      puts "Failed to take snapshot: #{error.localizedDescription}"
      NSApplication.sharedApplication.terminate nil
    end

    def webView(view, didFailProvisionalLoadWithError:error, forFrame:frame)
      puts "Failed to take snapshot: #{error.localizedDescription}"
      NSApplication.sharedApplication.terminate nil
    end
    
    def timed_out?
      @start ||= Time.now
      (Time.now.to_i - @start.to_i) > (config.timeout || 30) 
    end
    
    class BrowserView
      attr_accessor :view, :config
      
      def initialize(browser)
        @config = browser.config
        @view = WebView.alloc.initWithFrame([0, 0, config.width || 1024, config.height || 768])
        window = NSWindow.alloc.initWithContentRect([0, 0, config.width || 1024, config.height || 768],
          styleMask:NSBorderlessWindowMask, backing:NSBackingStoreBuffered, defer:false)
      
        window.setContentView view   
        # Use the screen stylesheet, rather than the print one.
        view.setMediaStyle 'screen' 
        # Set the user agent to Safari, to ensure we get back the exactly the same content as if we browsed
        # directly to the page
        view.setCustomUserAgent config.agent
        # Make sure we don't save any of the prefs that we change.
        view.preferences.setAutosaves(false)
        # Set some useful options.
        view.preferences.setShouldPrintBackgrounds(true)
        view.preferences.setJavaScriptCanOpenWindowsAutomatically(false)
        view.preferences.setAllowsAnimatedImages(false)
        # Make sure we don't get a scroll bar.
        view.mainFrame.frameView.setAllowsScrolling(false)
        view.setFrameLoadDelegate(browser)
      end
      
      def fetch(url)
    		view.mainFrame.loadRequest NSURLRequest.requestWithURL(NSURL.URLWithString(url))
      end
      
      def save_as(file, filetype = :pdf)
        docView = view.mainFrame.frameView.documentView
        width = config.width || docView.bounds.size.width
        height = config.height || docView.bounds.size.height
        docView.window.setContentSize([width, height])
        docView.setFrame(view.bounds)
        docView.setNeedsDisplay(true)
        docView.displayIfNeeded
        docView.lockFocus
        data_for_type(docView, filetype).writeToFile(file, atomically:true)
        docView.unlockFocus
      end
      
      def data_for_type(docView, filetype)
        case filetype
        when :pdf 
          docView.dataWithPDFInsideRect(docView.bounds) 
        when *BITMAP_TYPES.keys
          bitmap = NSBitmapImageRep.alloc.initWithFocusedViewRect(docView.bounds)
          bitmap.representationUsingType(BITMAP_TYPES[filetype], properties:nil)
        else
          raise "Unknown output type '#{filetype}'"
        end
      end
    end
  end
end

Snapper::CLI.run