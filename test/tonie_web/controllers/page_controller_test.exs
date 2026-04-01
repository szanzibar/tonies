defmodule TonieWeb.PageControllerTest do
  use TonieWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Tonie"
  end
end
