defmodule Tonie.YTMusic.ParserTest do
  use ExUnit.Case, async: true

  alias Tonie.YTMusic.Parser

  # --- Helper: build a minimal YouTube Music API response ---

  defp search_response(shelf_contents) do
    %{
      "contents" => %{
        "tabbedSearchResultsRenderer" => %{
          "tabs" => [
            %{
              "tabRenderer" => %{
                "content" => %{
                  "sectionListRenderer" => %{
                    "contents" => [
                      %{"musicShelfRenderer" => %{"contents" => shelf_contents}}
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    }
  end

  defp album_item(opts) do
    name = opts[:name] || "Test Album"
    artist = opts[:artist] || "Test Artist"
    year = opts[:year] || "2024"
    album_id = opts[:album_id] || "MPREb_test123"
    playlist_id = opts[:playlist_id] || "OLAK5uy_test"
    thumbnail_url = opts[:thumbnail] || "https://lh3.googleusercontent.com/thumb"

    %{
      "musicResponsiveListItemRenderer" => %{
        "flexColumns" => [
          %{
            "musicResponsiveListItemFlexColumnRenderer" => %{
              "text" => %{"runs" => [%{"text" => name}]}
            }
          },
          %{
            "musicResponsiveListItemFlexColumnRenderer" => %{
              "text" => %{
                "runs" => [
                  %{"text" => "Album"},
                  %{"text" => " • "},
                  %{
                    "text" => artist,
                    "navigationEndpoint" => %{
                      "browseEndpoint" => %{
                        "browseId" => "UC_artist_123",
                        "browseEndpointContextSupportedConfigs" => %{
                          "browseEndpointContextMusicConfig" => %{
                            "pageType" => "MUSIC_PAGE_TYPE_ARTIST"
                          }
                        }
                      }
                    }
                  },
                  %{"text" => " • "},
                  %{"text" => year}
                ]
              }
            }
          }
        ],
        "navigationEndpoint" => %{
          "browseEndpoint" => %{"browseId" => album_id}
        },
        "overlay" => %{
          "musicItemThumbnailOverlayRenderer" => %{
            "content" => %{
              "musicPlayButtonRenderer" => %{
                "playNavigationEndpoint" => %{
                  "watchPlaylistEndpoint" => %{"playlistId" => playlist_id}
                }
              }
            }
          }
        },
        "thumbnail" => %{
          "musicThumbnailRenderer" => %{
            "thumbnail" => %{
              "thumbnails" => [
                %{"url" => "#{thumbnail_url}=w60", "width" => 60},
                %{"url" => "#{thumbnail_url}=w226", "width" => 226}
              ]
            }
          }
        }
      }
    }
  end

  defp artist_item(opts) do
    name = opts[:name] || "Test Artist"
    artist_id = opts[:artist_id] || "UC_artist_123"
    subscribers = opts[:subscribers] || "1.2M subscribers"
    thumbnail_url = opts[:thumbnail] || "https://lh3.googleusercontent.com/artist"

    %{
      "musicResponsiveListItemRenderer" => %{
        "flexColumns" => [
          %{
            "musicResponsiveListItemFlexColumnRenderer" => %{
              "text" => %{"runs" => [%{"text" => name}]}
            }
          },
          %{
            "musicResponsiveListItemFlexColumnRenderer" => %{
              "text" => %{
                "runs" => [
                  %{"text" => "Artist"},
                  %{"text" => " • "},
                  %{"text" => subscribers}
                ]
              }
            }
          }
        ],
        "navigationEndpoint" => %{
          "browseEndpoint" => %{"browseId" => artist_id}
        },
        "thumbnail" => %{
          "musicThumbnailRenderer" => %{
            "thumbnail" => %{
              "thumbnails" => [
                %{"url" => "#{thumbnail_url}=w60", "width" => 60},
                %{"url" => "#{thumbnail_url}=w226", "width" => 226}
              ]
            }
          }
        }
      }
    }
  end

  defp album_browse_response(opts) do
    name = opts[:name] || "Great Album"
    artist = opts[:artist] || "Great Artist"
    year = opts[:year] || "2023"
    songs = opts[:songs] || "10 songs"
    duration = opts[:duration] || "32 minutes"
    tracks = opts[:tracks] || []

    track_items =
      Enum.map(tracks, fn {title, dur} ->
        %{
          "musicResponsiveListItemRenderer" => %{
            "flexColumns" => [
              %{
                "musicResponsiveListItemFlexColumnRenderer" => %{
                  "text" => %{"runs" => [%{"text" => title}]}
                }
              }
            ],
            "fixedColumns" => [
              %{
                "musicResponsiveListItemFixedColumnRenderer" => %{
                  "text" => %{"runs" => [%{"text" => dur}]}
                }
              }
            ]
          }
        }
      end)

    %{
      "contents" => %{
        "twoColumnBrowseResultsRenderer" => %{
          "tabs" => [
            %{
              "tabRenderer" => %{
                "content" => %{
                  "sectionListRenderer" => %{
                    "contents" => [
                      %{
                        "musicResponsiveHeaderRenderer" => %{
                          "title" => %{"runs" => [%{"text" => name}]},
                          "subtitle" => %{
                            "runs" => [
                              %{"text" => "Album"},
                              %{"text" => " • "},
                              %{"text" => year},
                              %{"text" => " • "},
                              %{
                                "text" => artist,
                                "navigationEndpoint" => %{
                                  "browseEndpoint" => %{"browseId" => "UC_artist_123"}
                                }
                              }
                            ]
                          },
                          "secondSubtitle" => %{
                            "runs" => [
                              %{"text" => songs},
                              %{"text" => " • "},
                              %{"text" => duration}
                            ]
                          },
                          "thumbnail" => %{
                            "musicThumbnailRenderer" => %{
                              "thumbnail" => %{
                                "thumbnails" => [
                                  %{"url" => "https://lh3.google.com/thumb=w226"}
                                ]
                              }
                            }
                          }
                        }
                      }
                    ]
                  }
                }
              }
            }
          ],
          "secondaryContents" => %{
            "sectionListRenderer" => %{
              "contents" => [
                %{
                  "musicShelfRenderer" => %{
                    "contents" => track_items
                  }
                }
              ]
            }
          }
        }
      }
    }
  end

  # --- parse_albums ---

  describe "parse_albums/1" do
    test "parses album search results" do
      data =
        search_response([
          album_item(name: "Paw Patrol", artist: "Various", year: "2020", album_id: "MPREb_paw")
        ])

      [album] = Parser.parse_albums(data)
      assert album.name == "Paw Patrol"
      assert album.artist == "Various"
      assert album.year == "2020"
      assert album.album_id == "MPREb_paw"
      assert album.playlist_id == "OLAK5uy_test"
      assert album.thumbnail =~ "w226"
    end

    test "parses multiple albums" do
      data =
        search_response([
          album_item(name: "Album 1"),
          album_item(name: "Album 2"),
          album_item(name: "Album 3")
        ])

      albums = Parser.parse_albums(data)
      assert length(albums) == 3
      assert Enum.map(albums, & &1.name) == ["Album 1", "Album 2", "Album 3"]
    end

    test "returns empty list for empty response" do
      data = search_response([])
      assert Parser.parse_albums(data) == []
    end

    test "returns empty list when shelf is missing" do
      data = %{"contents" => %{"tabbedSearchResultsRenderer" => %{"tabs" => []}}}
      assert Parser.parse_albums(data) == []
    end
  end

  # --- parse_artists ---

  describe "parse_artists/1" do
    test "parses artist search results" do
      data =
        search_response([
          artist_item(name: "Globi", artist_id: "UC_globi", subscribers: "50K subscribers")
        ])

      [artist] = Parser.parse_artists(data)
      assert artist.name == "Globi"
      assert artist.artist_id == "UC_globi"
      assert artist.subscribers == "50K subscribers"
      assert artist.thumbnail =~ "w226"
    end

    test "returns empty list for no results" do
      data = search_response([])
      assert Parser.parse_artists(data) == []
    end
  end

  # --- parse_album_duration ---

  describe "parse_album_duration/1" do
    test "extracts songs count and duration text" do
      data = album_browse_response(songs: "12 songs", duration: "45 minutes, 30 seconds")
      result = Parser.parse_album_duration(data)
      assert result.songs == "12 songs"
      assert result.duration_text == "45 minutes, 30 seconds"
    end

    test "handles single song" do
      data = album_browse_response(songs: "1 song", duration: "3 minutes, 45 seconds")
      result = Parser.parse_album_duration(data)
      assert result.songs == "1 song"
    end

    test "handles missing header gracefully" do
      data = %{"contents" => %{"twoColumnBrowseResultsRenderer" => %{"tabs" => []}}}
      result = Parser.parse_album_duration(data)
      assert result.songs == nil
      assert result.duration_text == nil
    end
  end

  # --- parse_album_page ---

  describe "parse_album_page/1" do
    test "extracts full album details" do
      data =
        album_browse_response(
          name: "Frozen Soundtrack",
          artist: "Various Artists",
          year: "2013",
          songs: "32 songs",
          duration: "1 hour, 15 minutes",
          tracks: [
            {"Let It Go", "3:44"},
            {"Do You Want to Build a Snowman?", "3:26"},
            {"For the First Time in Forever", "3:45"}
          ]
        )

      result = Parser.parse_album_page(data)
      assert result.name == "Frozen Soundtrack"
      assert result.artist == "Various Artists"
      assert result.year == "2013"
      assert result.songs == "32 songs"
      assert result.duration_text == "1 hour, 15 minutes"
      assert result.thumbnail =~ "lh3.google"
      assert length(result.tracks) == 3
      assert hd(result.tracks) == %{title: "Let It Go", duration: "3:44"}
    end

    test "handles album with no tracks" do
      data = album_browse_response(tracks: [])
      result = Parser.parse_album_page(data)
      assert result.tracks == []
    end

    test "handles missing data gracefully" do
      data = %{"contents" => %{"twoColumnBrowseResultsRenderer" => %{"tabs" => []}}}
      result = Parser.parse_album_page(data)
      assert result.name == nil
      assert result.artist == nil
      assert result.tracks == []
    end
  end

  # --- parse_artist_page ---

  describe "parse_artist_page/1" do
    test "extracts artist name and thumbnail" do
      data = %{
        "header" => %{
          "musicImmersiveHeaderRenderer" => %{
            "title" => %{"runs" => [%{"text" => "Paw Patrol"}]},
            "thumbnail" => %{
              "musicThumbnailRenderer" => %{
                "thumbnail" => %{
                  "thumbnails" => [
                    %{"url" => "https://lh3.google.com/small", "width" => 226},
                    %{"url" => "https://lh3.google.com/large", "width" => 1440}
                  ]
                }
              }
            }
          }
        },
        "contents" => %{
          "singleColumnBrowseResultsRenderer" => %{
            "tabs" => [
              %{
                "tabRenderer" => %{
                  "content" => %{
                    "sectionListRenderer" => %{"contents" => []}
                  }
                }
              }
            ]
          }
        }
      }

      result = Parser.parse_artist_page(data)
      assert result.name == "Paw Patrol"
      assert result.thumbnail == "https://lh3.google.com/large"
      assert result.albums == []
      assert result.albums_browse_id == nil
      assert result.albums_params == nil
    end

    test "handles missing header gracefully" do
      data = %{
        "header" => %{},
        "contents" => %{
          "singleColumnBrowseResultsRenderer" => %{
            "tabs" => [
              %{
                "tabRenderer" => %{
                  "content" => %{
                    "sectionListRenderer" => %{"contents" => []}
                  }
                }
              }
            ]
          }
        }
      }

      result = Parser.parse_artist_page(data)
      assert result.name == nil
      assert result.thumbnail == nil
    end
  end

  # --- parse_artist_albums (grid) ---

  describe "parse_artist_albums/1" do
    test "parses grid album items" do
      data = %{
        "contents" => %{
          "singleColumnBrowseResultsRenderer" => %{
            "tabs" => [
              %{
                "tabRenderer" => %{
                  "content" => %{
                    "sectionListRenderer" => %{
                      "contents" => [
                        %{
                          "gridRenderer" => %{
                            "items" => [
                              %{
                                "musicTwoRowItemRenderer" => %{
                                  "title" => %{"runs" => [%{"text" => "Album One"}]},
                                  "subtitle" => %{
                                    "runs" => [
                                      %{"text" => "Album"},
                                      %{"text" => " • "},
                                      %{"text" => "2023"}
                                    ]
                                  },
                                  "navigationEndpoint" => %{
                                    "browseEndpoint" => %{"browseId" => "MPREb_one"}
                                  },
                                  "thumbnailOverlay" => %{
                                    "musicItemThumbnailOverlayRenderer" => %{
                                      "content" => %{
                                        "musicPlayButtonRenderer" => %{
                                          "playNavigationEndpoint" => %{
                                            "watchPlaylistEndpoint" => %{
                                              "playlistId" => "OLAK_one"
                                            }
                                          }
                                        }
                                      }
                                    }
                                  },
                                  "thumbnailRenderer" => %{
                                    "musicThumbnailRenderer" => %{
                                      "thumbnail" => %{
                                        "thumbnails" => [
                                          %{"url" => "https://lh3.google.com/grid_thumb"}
                                        ]
                                      }
                                    }
                                  }
                                }
                              }
                            ]
                          }
                        }
                      ]
                    }
                  }
                }
              }
            ]
          }
        }
      }

      [album] = Parser.parse_artist_albums(data)
      assert album.name == "Album One"
      assert album.year == "2023"
      assert album.type == "Album"
      assert album.album_id == "MPREb_one"
      assert album.playlist_id == "OLAK_one"
    end

    test "returns empty list when grid is missing" do
      data = %{
        "contents" => %{
          "singleColumnBrowseResultsRenderer" => %{
            "tabs" => [
              %{
                "tabRenderer" => %{
                  "content" => %{
                    "sectionListRenderer" => %{"contents" => []}
                  }
                }
              }
            ]
          }
        }
      }

      assert Parser.parse_artist_albums(data) == []
    end
  end
end
