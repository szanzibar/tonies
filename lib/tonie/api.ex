defmodule Tonie.Api do
  @api_url "https://api.tonie.cloud/v2/"

  def init do
    token = auth()
    household_id = get_household(token)
    tonies = list_creative_tonies(token, household_id)
    wizard = hd(tonies)

    %{token: token, household_id: household_id, tonies: tonies, wizard: wizard}
  end

  @doc """
  Authenticates with tonie api and returns bearer token
  """
  def auth do
    auth_url = "https://login.tonies.com/auth/realms/tonies/protocol/openid-connect/token"

    data = %{
      "grant_type" => "password",
      "client_id" => "my-tonies",
      "scope" => "openid",
      "username" => Application.fetch_env!(:tonie, :tonie_username),
      "password" => Application.fetch_env!(:tonie, :tonie_password)
    }

    %{body: %{"access_token" => token}} = Req.post!(auth_url, form: data)
    token
  end

  @doc """
  Assumes 1 household and returns the household id
  """
  def get_household(token) do
    url = "#{@api_url}households"

    %{body: [%{"id" => id}]} = Req.get!(url, auth: {:bearer, token})
    id
  end

  @doc """
  Returns the list of creative tonies for the given household
  """
  def list_creative_tonies(token, household_id) do
    url = "#{@api_url}households/#{household_id}/creativetonies"

    %{body: tonies} = Req.get!(url, auth: {:bearer, token})

    Enum.map(tonies, fn tonie ->
      chapters = Enum.map(tonie["chapters"], & &1["title"])

      chapter_data =
        Enum.map(tonie["chapters"], fn c ->
          %{"title" => c["title"], "file" => c["file"]}
        end)

      %{
        "id" => tonie["id"],
        "imageUrl" => tonie["imageUrl"],
        "chapters" => chapters,
        "chapter_data" => chapter_data,
        "secondsPresent" => tonie["secondsPresent"] || 0,
        "secondsRemaining" => tonie["secondsRemaining"] || 0
      }
    end)
  end

  def clear_creative_tonie(token, household_id, tonie) do
    url = "#{@api_url}households/#{household_id}/creativetonies/#{tonie["id"]}"

    Req.patch!(url, json: %{chapters: []}, auth: {:bearer, token})
    :ok
  end

  @doc """
  Adds a chapter to a tonie using an existing file_id (used for prepend to re-add old chapters)
  """
  def add_chapter(token, household_id, tonie, title, file_id) do
    chapters_url = "#{@api_url}households/#{household_id}/creativetonies/#{tonie["id"]}/chapters"

    Req.post!(chapters_url, json: %{title: title, file: file_id}, auth: {:bearer, token})
  end

  def upload_file(token, household_id, tonie, file_path) do
    url = "https://api.tonie.cloud/v2/file"
    # Guess MIME type based on file extension
    mime_type =
      case Path.extname(file_path) do
        ".mp3" -> "audio/mpeg"
        ".wav" -> "audio/wav"
        ".aac" -> "audio/aac"
        ".m4a" -> "audio/mp4"
        ".ogg" -> "audio/ogg"
        ".opus" -> "audio/ogg"
        ".webm" -> "audio/webm"
        _ -> "application/octet-stream"
      end

    %{body: %{"fileId" => file_id, "request" => %{"fields" => fields, "url" => upload_url}}} =
      Req.post!(url, auth: {:bearer, token})

    file_content = File.read!(file_path)

    form_data =
      Map.to_list(fields) ++
        [file: {file_content, filename: file_id, content_type: mime_type}]

    %{status: 204} = Req.post!(upload_url, form_multipart: form_data)

    # assign file to tonie
    title = Path.basename(file_path, Path.extname(file_path))

    chapters_url = "#{@api_url}households/#{household_id}/creativetonies/#{tonie["id"]}/chapters"

    Req.post!(chapters_url, json: %{title: title, file: file_id}, auth: {:bearer, token})
  end
end
