# This script overrides a method in the Blacklight gem
# I'm querying DLib's solr via ezproxy, which requires the use of an ezproxy session cookie
# and there's no provision for sending arbitrary http headers (e.g. cookies) along with solr
# http requests, so I'm overriding the Blacklight method that handles solr http requests
# and introducing an ezproxy session cookie into the http header
Blacklight::SolrRepository.class_eval do
  def send_and_receive(path, solr_params = {})
      benchmark("Solr fetch", level: :debug) do
        key = blacklight_config.http_method == :post ? :data : :params
        # if we are in the ferglocaldev environment then we need to obtain an ezproxy session token 
        # before we can run any solr queries
        if Rails.env.ferglocaldev?
          ezproxycookie = ezproxy_session_token
          res = connection.send_and_receive(path, {key=>solr_params.to_hash, method: blacklight_config.http_method, :headers=>{"Cookie"=>"#{ezproxycookie}"}})
        else
          res = connection.send_and_receive(path, {key=>solr_params.to_hash, method: blacklight_config.http_method})
        end
        solr_response = blacklight_config.response_model.new(res, solr_params, document_model: blacklight_config.document_model, blacklight_config: blacklight_config)

        Blacklight.logger.debug("Solr query: #{blacklight_config.http_method} #{path} #{solr_params.to_hash.inspect}")
        Blacklight.logger.debug("Solr response: #{solr_response.inspect}") if defined?(::BLACKLIGHT_VERBOSE_LOGGING) and ::BLACKLIGHT_VERBOSE_LOGGING
        solr_response
      end
    rescue Errno::ECONNREFUSED => e
      raise Blacklight::Exceptions::ECONNREFUSED.new("Unable to connect to Solr instance using #{connection.inspect}: #{e.inspect}")
    rescue RSolr::Error::Http => e
      raise Blacklight::Exceptions::InvalidRequest.new(e.message)
  end

  # If an ezproxy session id doesn't exist in the Rails global cache, make an http request to ezproxy, filter
  # out the session cookie, store it in the cache, and return it
  def ezproxy_session_token
    # check to see if an ezproxy session token exists in the cache
    ezproxy_cookie = Rails.cache.fetch("ezproxy_cookie")
    if ezproxy_cookie == nil 
      # make a call to the ezproxy login page and fetch the cookie it tries to set
      uri = URI.parse("https://login.ezproxy.york.ac.uk/login?url=http://dlib.york.ac.uk/solr/")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      ezproxy_cookie = response['set-cookie'].split('; ')[0]
      # store that cookie in the cache
      Rails.cache.fetch("ezproxy_cookie", expires_in: 1.hours) do
        ezproxy_cookie
      end
    end    
    ezproxy_cookie
  end
end

