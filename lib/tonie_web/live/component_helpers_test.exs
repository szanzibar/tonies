defmodule TonieWeb.ComponentHelpersTest do
  use ExUnit.Case, async: true

  alias TonieWeb.ComponentHelpers

  describe "thumb/1" do
    test "encodes URL to base64url thumbnail path" do
      url = "https://lh3.googleusercontent.com/some-thumbnail"
      result = ComponentHelpers.thumb(url)
      assert String.starts_with?(result, "/thumb/")

      # Decode it back
      encoded = String.replace_prefix(result, "/thumb/", "")
      assert Base.url_decode64!(encoded, padding: false) == url
    end

    test "different URLs produce different paths" do
      assert ComponentHelpers.thumb("https://a.com/1.jpg") !=
               ComponentHelpers.thumb("https://b.com/2.jpg")
    end

    test "returns nil for nil input" do
      assert ComponentHelpers.thumb(nil) == nil
    end

    test "returns nil for non-binary input" do
      assert ComponentHelpers.thumb(123) == nil
      assert ComponentHelpers.thumb(%{}) == nil
    end

    test "returns nil for empty or blank URL input" do
      assert ComponentHelpers.thumb("") == nil
      assert ComponentHelpers.thumb("   ") == nil
    end

    test "returns nil for non-https URLs" do
      assert ComponentHelpers.thumb("http://example.com/img.jpg") == nil
      assert ComponentHelpers.thumb("ftp://example.com/img.jpg") == nil
      assert ComponentHelpers.thumb("/local/path.jpg") == nil
    end

    test "handles URLs with special characters" do
      url = "https://example.com/img?size=500&format=jpg"
      result = ComponentHelpers.thumb(url)
      encoded = String.replace_prefix(result, "/thumb/", "")
      assert Base.url_decode64!(encoded, padding: false) == url
    end

    test "trims surrounding whitespace for valid HTTPS URLs" do
      url = "https://example.com/cover.jpg"
      result = ComponentHelpers.thumb("  #{url}  ")
      encoded = String.replace_prefix(result, "/thumb/", "")
      assert Base.url_decode64!(encoded, padding: false) == url
    end
  end
end
