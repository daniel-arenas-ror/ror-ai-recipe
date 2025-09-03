# frozen_string_literal: true

require 'httparty' # Still useful for other HTTP calls if needed, but not for video download
require 'uri'
require 'nokogiri'
require 'fileutils' # For creating directories if needed
require 'selenium-webdriver' # For browser automation
require 'webdrivers' # Automatically downloads browser drivers (e.g., ChromeDriver)
require 'base64' # For encoding/decoding blob data

# This script allows you to scrape an Instagram post URL for a video,
# download the video using a headless browser, and then pass it to an AI processing method.
#
# Dependencies:
# - httparty: `gem install httparty`
# - nokogiri: `gem install nokogiri`
# - selenium-webdriver: `gem install selenium-webdriver`
# - webdrivers: `gem install webdrivers` (Automatically manages browser drivers like ChromeDriver)
#
# Usage Example:
#   scraper = InstagramVideoScraper.new("https://www.instagram.com/p/DIApaK4pbPT/")
#   scraper.scrape_and_download
class InstagramVideoScraper
  INSTAGRAM_BASE_URL = 'https://www.instagram.com' # Not directly used for scraping, but good for context
  VIDEO_DOWNLOAD_TIMEOUT = 30 # Seconds to wait for video to load/download

  def initialize(instagram_url)
    @instagram_url = instagram_url
    @download_dir = 'downloaded_videos'
    FileUtils.mkdir_p(@download_dir) unless File.directory?(@download_dir)
    @driver = nil # Selenium WebDriver instance
  end

  # Orchestrates the scraping, downloading, and AI processing of the video.
  def scrape_and_download
    puts "Starting video scraping for: #{@instagram_url}"

    begin
      initialize_browser
      navigate_to_instagram_page

      video_url = extract_video_url_with_selenium
      if video_url && video_url.start_with?('blob:')
        puts "Found dynamic video URL (blob): #{video_url}"
        downloaded_file_path = download_blob_video(video_url)
        if downloaded_file_path
          puts "Video downloaded to: #{downloaded_file_path}"
          process_video_with_ai(downloaded_file_path)
        else
          puts "Failed to download video from #{video_url}"
        end
      elsif video_url # Fallback for direct video URLs if Instagram changes
        puts "Found direct video URL: #{video_url}"
        # You could use HTTParty here if it's a direct URL, but for consistency
        # and since the request was for blob, we'll stick to selenium for now.
        # If Instagram reverts to direct URLs in og:video, HTTParty might be faster.
        puts "Direct video URLs are not handled by this Selenium-based download method."
        puts "This script is designed for 'blob:' URLs which require browser interaction."
      else
        puts "No video found on the Instagram page, or could not extract video URL."
        puts "Make sure the URL is a public video post."
      end
    rescue Selenium::WebDriver::Error::WebDriverError => e
      puts "Selenium WebDriver error: #{e.message}"
      puts "Ensure you have a compatible browser (e.g., Chrome) and its driver installed."
    rescue StandardError => e
      puts "An error occurred: #{e.message}"
      puts e.backtrace.join("\n")
    ensure
      quit_browser
    end
  end

  private

  # Initializes a headless Chrome browser using Selenium.
  def initialize_browser
    puts "Initializing headless Chrome browser..."
    Webdrivers::Chromedriver.required_version = '120.0.6099.109'

    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless') # Run Chrome in headless mode (no UI)
    options.add_argument('--disable-gpu') # Recommended for headless
    options.add_argument('--no-sandbox') # Recommended for CI/CD environments
    options.add_argument('--disable-dev-shm-usage') # Overcomes limited resource problems
    options.add_argument('--window-size=1920,1080') # Set a consistent window size

    # Automatically download and manage ChromeDriver
    Webdrivers::Chromedriver.update

    @driver = Selenium::WebDriver.for :chrome, options: options
    @driver.manage.timeouts.implicit_wait = 10 # seconds
    puts "Browser initialized."
  end

  # Navigates to the Instagram page and waits for content to load.
  def navigate_to_instagram_page
    puts "Navigating to #{@instagram_url}"
    @driver.navigate.to(@instagram_url)
    # Wait for the video element to be present on the page
    wait = Selenium::WebDriver::Wait.new(timeout: VIDEO_DOWNLOAD_TIMEOUT)
    wait.until { @driver.find_element(css: 'video').displayed? }
    puts "Page loaded and video element found."
  end

  # Extracts the video URL (potentially a blob URL) from the <video> tag using Selenium.
  # @return [String, nil] The video URL, or nil if not found.
  def extract_video_url_with_selenium
    video_element = @driver.find_element(css: 'video')
    video_element['src']
  rescue Selenium::WebDriver::Error::NoSuchElementError
    puts "Video element not found on the page."
    nil
  end

  # Downloads the video from a blob URL by executing JavaScript in the browser.
  # The JavaScript fetches the blob, converts it to base64, and returns it to Ruby.
  # @param blob_url [String] The blob URL of the video.
  # @return [String, nil] The path to the downloaded file, or nil if download fails.
  def download_blob_video(blob_url)
    puts "Attempting to download blob video from: #{blob_url}"

    # JavaScript to fetch blob data and convert to base64
    # This script resolves the blob URL, fetches its content as an ArrayBuffer,
    # and then converts that ArrayBuffer to a Base64 string.
    js_script = <<-JS
      return new Promise((resolve, reject) => {
        fetch('#{blob_url}')
          .then(response => response.blob())
          .then(blob => {
            const reader = new FileReader();
            reader.onloadend = () => {
              // reader.result will be a data URL (e.g., "data:video/mp4;base64,...")
              // We only need the base64 part, so we split by ','
              resolve(reader.result.split(',')[1]);
            };
            reader.onerror = reject;
            reader.readAsDataURL(blob);
          })
          .catch(error => reject(error.message));
      });
    JS

    # Execute the JavaScript and get the base64 encoded video data
    base64_data = @driver.execute_script(js_script)

    unless base64_data
      puts "Failed to retrieve base64 data from blob."
      return nil
    end

    # Decode base64 data and save to file
    decoded_data = Base64.decode64(base64_data)

    # Generate a unique filename
    file_name = "instagram_video_#{Time.now.to_i}.mp4"
    output_path = File.join(@download_dir, file_name)

    puts "Saving decoded video to: #{output_path}"
    File.binwrite(output_path, decoded_data)
    output_path
  rescue StandardError => e
    puts "Error downloading blob video: #{e.message}"
    nil
  end

  # Quits the browser instance.
  def quit_browser
    if @driver
      puts "Quitting browser."
      @driver.quit
      @driver = nil
    end
  end

  # Placeholder method for sending the video to an Artificial Intelligence.
  # This method should be implemented with your chosen AI service (e.g., Google Cloud Video AI, AWS Transcribe).
  # @param video_path [String] The local path to the downloaded video file.
  def process_video_with_ai(video_path)
    puts "\n--- AI Processing Placeholder ---"
    puts "Video ready for AI processing: #{video_path}"
    puts "Implement your AI integration here to translate and get text from the video."
    puts "This might involve uploading the video to a cloud service (e.g., Google Cloud Storage, AWS S3)"
    puts "and then calling an AI API (e.g., Google Cloud Video AI, AWS Transcribe, OpenAI Whisper)."
    # Example:
    # ai_service = YourAIService.new
    # transcription_result = ai_service.transcribe_video(video_path)
    # translation_result = ai_service.translate_text(transcription_result)
    # puts "Transcription: #{transcription_result}"
    # puts "Translation: #{translation_result}"
    puts "---------------------------------\n"
  end
end

# Example Usage:
# To run this script, save it as, e.g., `instagram_scraper.rb`
# and execute from your terminal: `ruby instagram_scraper.rb`
#
# IMPORTANT:
# 1. Ensure you have Chrome browser installed on your system.
# 2. Install required gems:
#    `gem install httparty nokogiri selenium-webdriver webdrivers`
# 3. Replace the example URL with a public Instagram video post URL.
#    Note that Instagram's structure can change, potentially breaking the scraper.
if __FILE__ == $PROGRAM_NAME
  # IMPORTANT: Replace this with an actual public Instagram video URL.
  # This example URL is just a placeholder and will not work.
  # Example: "https://www.instagram.com/reel/C8y4z2gO_o7/"
  instagram_video_url = ARGV[0] || "https://www.instagram.com/p/C8y4z2gO_o7/" # Placeholder URL

  if instagram_video_url == "https://www.instagram.com/p/C8y4z2gO_o7/"
    puts "WARNING: Using a placeholder Instagram URL. Please provide a real public video URL as an argument."
    puts "Example: ruby instagram_scraper.rb https://www.instagram.com/reel/YOUR_VIDEO_ID/"
  end

  if instagram_video_url.nil? || !instagram_video_url.start_with?('http')
    puts "Usage: ruby instagram_scraper.rb <instagram_video_url>"
  else
    scraper = InstagramVideoScraper.new(instagram_video_url)
    scraper.scrape_and_download
  end
end
