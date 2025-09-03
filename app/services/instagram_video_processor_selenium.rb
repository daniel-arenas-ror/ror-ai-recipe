require 'selenium-webdriver'
require 'webdrivers'
require 'tempfile'
require 'open-uri'

class InstagramVideoProcessorSelenium
  def initialize(instagram_url)
    @instagram_url = instagram_url
    @driver = nil
  end

  def process
    setup_driver
    video_url = extract_video_url_with_selenium(@instagram_url)
    p " video_url #{video_url}"
    
    return unless video_url

    video_file = download_video(video_url)
    p " video_file #{video_file}"
    return unless video_file

    ai_result = process_with_ai(video_file)
    video_file.close
    video_file.unlink
    ai_result
  ensure
    cleanup_driver
  end

  private

  def setup_driver
    # Configure webdrivers to use a specific ChromeDriver version if needed
    # Uncomment the line below and set a specific version if you continue to have issues
    Webdrivers::Chromedriver.required_version = '120.0.6099.109'
    
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    options.add_argument('--window-size=1920,1080')
    options.add_argument('--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

    @driver = Selenium::WebDriver.for :chrome, options: options
    @driver.manage.timeouts.implicit_wait = 10
    @driver.manage.timeouts.page_load = 30
  end

  def cleanup_driver
    @driver&.quit
  end

  def extract_video_url_with_selenium(url)
    @driver.get(url)
    
    # Wait for page to load
    sleep 3
    
    # Wait for video element to be present
    wait = Selenium::WebDriver::Wait.new(timeout: 15)
    
    begin
      # Try to find video element
      video_element = wait.until { @driver.find_element(css: 'video') }
      p "Found video element: #{video_element}"
      
      # Get the src attribute
      video_src = video_element.attribute('src')
      p "Video src: #{video_src}"
      
      if video_src && !video_src.start_with?('blob:')
        return video_src
      end
      
      # If it's a blob URL, try to get the actual video URL from network requests
      # or look for other video sources
      return extract_video_from_network_requests
      
    rescue Selenium::WebDriver::Error::TimeoutError
      p "Timeout waiting for video element"
      return nil
    end
  end

  def extract_video_from_network_requests
    # Get all video elements and their sources
    video_elements = @driver.find_elements(css: 'video')
    p "Found #{video_elements.length} video elements"
    
    video_elements.each do |video|
      src = video.attribute('src')
      p "Video src: #{src}"
      
      # Look for video URLs in the page source
      if src && src.include?('.mp4')
        return src
      end
    end
    
    # Try to find video URLs in the page source
    page_source = @driver.page_source
    p "Page source length: #{page_source.length}"
    
    # Look for common video URL patterns
    video_urls = page_source.scan(/https?:\/\/[^"'\s]+\.(?:mp4|mov|avi|webm)/i)
    p "Found video URLs in page source: #{video_urls}"
    
    return video_urls.first if video_urls.any?
    
    # Try to find video in meta tags
    meta_video = @driver.find_elements(css: 'meta[property="og:video"]')
    meta_video.each do |meta|
      content = meta.attribute('content')
      p "Meta video content: #{content}"
      return content if content && content.include?('.mp4')
    end
    
    nil
  end

  def download_video(video_url)
    file = Tempfile.new(['instagram_video', '.mp4'])
    file.binmode
    
    begin
      URI.open(video_url, 'rb') do |read_file|
        file.write(read_file.read)
      end
      file.rewind
      file
    rescue => e
      Rails.logger.error("Failed to download video: #{e.message}")
      file.close if file
      file.unlink if file
      nil
    end
  end

  def process_with_ai(video_file)
    # TODO: Integrate with your chosen AI service here
    # Example: send video_file.path to AI and return result
    raise NotImplementedError, 'AI processing not implemented yet.'
  end
end 