require "uri"
require_relative "../atproto/requests"
require "xrpc"
# module Bskyrb
#   include Atmosfire

#   class Client
#     include RequestUtils
#     attr_reader :session

#     def initialize(session)
#       @session = session
#     end
#   end
# end

module Bskyrb
  module PostTools
    MENTION_PATTERN = /(^|\s|\()(@)([a-zA-Z0-9.-]+)(\b)/
    LINK_PATTERN = URI.regexp(['http', 'https'])
    HASHTAG_PATTERN = /\#[^\s]+/

    def create_facets(text)
      facets = []

      facets += mention_facets(text)
      facets += link_facets(text)
      facets += hashtag_facets(text)

      facets.empty? ? nil : facets
    end

    private

    def scan(text, pattern)
      text.enum_for(:scan, pattern).map do |match|
        index_start = Regexp.last_match.byteoffset(0).first
        index_end = Regexp.last_match.byteoffset(0).last
        [index_start, index_end, match]
      end
    end

    def mention_facets(text)
      scan(text, MENTION_PATTERN).map do |index_start, index_end, match|
        did = resolve_handle(@pds, (match.join("").strip)[1..-1])["did"]
        next if did.nil?

        {
          "$type" => "app.bsky.richtext.facet",
          "index" => {
            "byteStart" => index_start,
            "byteEnd" => index_end,
          },
          "features" => [
            {
              "did" => did, # this is the matched mention
              "$type" => "app.bsky.richtext.facet#mention",
            },
          ],
        }
      end.compact
    end

    def link_facets(text)
      scan(text, LINK_PATTERN).map do |index_start, index_end, match|
        match.compact!
        schema = match[0]
        path = "#{match[1]}#{match[2..-1].join("")}".strip
        {
          "$type" => "app.bsky.richtext.facet",
          "index" => {
            "byteStart" => index_start,
            "byteEnd" => index_end,
          },
          "features" => [
            {
              "uri" => URI.parse("#{schema}://#{path}/").normalize.to_s, # this is the matched link
              "$type" => "app.bsky.richtext.facet#link",
            },
          ],
        }
      end
    end

    def hashtag_facets(text)
      scan(text, HASHTAG_PATTERN).map do |index_start, index_end, match|
        {
          "$type" => "app.bsky.richtext.facet",
          "index" => {
            "byteStart" => index_start,
            "byteEnd" => index_end,
          },
          "features" => [
            {
              "tag" => match,
              "$type" => "app.bsky.richtext.facet#tag",
            },
          ],
        }
      end
    end
  end
end

module Bskyrb
  class PostRecord
    include ATProto::RequestUtils
    include PostTools
    attr_accessor :text, :timestamp, :facets, :embed, :pds

    def initialize(text, timestamp: DateTime.now.iso8601(3), pds: "https://bsky.social")
      @text = text
      @timestamp = timestamp
      @pds = pds
    end

    def to_json_hash
      {
        text: @text,
        createdAt: @timestamp,
        "$type": "app.bsky.feed.post",
        facets: @facets,
      }
    end

    def create_facets!
      @facets = create_facets(@text)
    end
  end
end
