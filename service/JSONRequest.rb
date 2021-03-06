# Copyright 2006-2009, Yahoo!
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are
#  met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#  3. Neither the name of Yahoo! nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
#  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
#  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
#   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
#  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
#  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
#  IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#
# A BrowserPlus service implements client side elements of the JSONRequest
# specification by Douglas Crockford, spec available here:
# http://json.org/JSONRequest.html
#

require 'net/http'
require 'uri'

bp_require 'json/json'

class JSONRequestInstance
  # args contains 'url', 'data_dir', 'temp_dir'
  def initialize(args)
    @base_uri = args['uri']
  end

  def doFetch(url, send, timeout, bp)
    # manage timemout (in milliseconds)
    if timeout == nil
      timeout = 10
    elsif timeout < 0
      bp.error("JSONRequestError", "bad timeout")
      return
    else
      timeout = timeout.to_f / 1000.0
    end

    Thread.new(url, send, timeout, bp) { |ui, s, t, b|
      begin
        # abosolutify uri
        base = URI.parse(@base_uri)
        url = base.merge(ui).to_s
        u = URI.parse(url)

        if url == nil
          bp.error("JSONRequestError", "bad URL")
          return
        end

        send = nil
        send = JSON.generate(s) if s != nil

        @proxy_server = @proxy_port = nil
        case RUBY_PLATFORM.split('-').last
          when 'mswin32', 'cygwin':
            begin
              bp_require 'win32/registry'
              Win32::Registry::HKEY_CURRENT_USER.open('Software\Microsoft\Windows\CurrentVersion\Internet Settings') do |node|
                begin
                  # Split and sort by type so that HTTP(S) comes before SOCKS.
                  proxies = node.read('ProxyServer')[1].split(';').sort
                  proxies.each do |candidate|
                    if candidate =~ /=/ then
                      proxy_type, proxy = candidate.split('=')
                    else
                      proxy_type = nil
                      proxy = candidate
                    end
                    @proxy_server, @proxy_port = proxy.split(':')
                    # Use the HTTP(S) proxy over SOCKS proxy if both are specified.
                    case proxy_type
                      when nil:
                        begin
                          bp_log('info', "Same proxy for HTTP, HTTPS & FTP - #{@proxy_server}:#{@proxy_port}")
                          @proxy = Net::HTTP::Proxy(@proxy_server, @proxy_port)
                          break
                        end
                      when 'http', 'https'
                        if proxy_type == u.scheme then
                          bp_log('info', "#{proxy_type.upcase} proxy - #{@proxy_server}:#{@proxy_port}")
                          @proxy = Net::HTTP::Proxy(@proxy_server, @proxy_port)
                          break
                        end
                      when 'socks':
                        begin
                          bp_log('info', "SOCKS proxy - #{@proxy_server}:#{@proxy_port}")
                          bp_require 'socksify/socksify_debug'
                          bp_require 'socksify/socksify'
                          TCPSocket::socks_server = @proxy_server
                          TCPSocket::socks_port = @proxy_port
                          @proxy = Net::HTTP::Proxy(nil)
                          break
                        end
                    end
                  end
                end if node.read('ProxyEnable')[1] == 1
              end
            end
        end

        @proxy.start(u.host, u.port) do |http|
          http.open_timeout = t
          http.read_timeout = t
          headers = {
            'Content-Type'     => 'application/jsonrequest',
            'Accept'           => 'application/jsonrequest',
            'Content-Encoding' => 'identity',
            'User-Agent'       => 'Yahoo! BrowserPlus'
          }
          path = (u.path == nil || u.path.empty?) ? "/" : u.path
          path += ("?" + u.query) if u.query
          if send
            req = Net::HTTP::Post.new(path, headers)
          else
            req = Net::HTTP::Get.new(path, headers)
          end

          res = http.request(req, send)

          if res.code != "200"
            bp_log('warn', "res.code => #{res.code}")
            b.error("JSONRequestError", "not ok")
            return
          end

          obj = JSON.parse(res.body)
          bp.complete(obj);
        end
      rescue Timeout::Error, EOFError
        bp.error("JSONRequestError", "no response")
      rescue JSON::ParserError
        bp.error("JSONRequestError", "bad response")
      rescue URI::InvalidURIError, Errno::ECONNREFUSED  => e
        bp.error("JSONRequestError", "bad URL")
      rescue Exception => e
        # uh oh, log and return bad url.
        bp_log('warn', "Unexpected exception (#{e.class}) for '#{ui}': #{e.to_s}")
        bp.error("JSONRequestError", "bad URL")
      end
    }
  end

  def get(bp, args)
    doFetch(args['url'], nil,
            args.has_key?("timeout") ? args['timeout'] : nil,
            bp)
  end

  def post(bp, args)
    doFetch(args['url'], args['send'],
            args.has_key?("timeout") ? args['timeout'] : nil,
            bp)
  end
end

rubyCoreletDefinition = {
  'class' => "JSONRequestInstance",
  'name' => "JSONRequest",
  'major_version' => 1,
  'minor_version' => 1,
  'micro_version' => 1,
  'documentation' => 'Allows secure cross-domain JSON requests, inspired by http://www.json.org/JSONRequest.html.',
  'functions' =>
  [
   {
     'name' => 'post',
     'documentation' => "Perform a JSON POST request.",
     'arguments' =>
     [
      {
        'name' => 'url',
        'type' => 'string',
        'documentation' => 'The URL to fetch.',
        'required' => true
      },
      {
        'name' => 'send',
        'type' => 'any',
        'documentation' => 'The JSON object to send.',
        'required' => true
      },
      {
        'name' => 'timeout',
        'type' => 'integer',
        'documentation' => 'The number of milliseconds to wait for the response. This parameter is optional. The default is 10000 (10 seconds).',
        'required' => false
      }
     ]
   },
   {
     'name' => 'get',
     'documentation' => "Perform a JSON GET request.",
     'arguments' =>
     [
      {
        'name' => 'url',
        'type' => 'string',
        'documentation' => 'The URL to fetch.',
        'required' => true
      },
      {
        'name' => 'timeout',
        'type' => 'integer',
        'documentation' => 'The number of milliseconds to wait for the response. This parameter is optional. The default is 10000 (10 seconds).',
        'required' => false
      }
     ]
   }
  ]
}
