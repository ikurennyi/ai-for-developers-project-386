class FrontendController < ApplicationController
  def show
    response.headers["Cache-Control"] = "no-cache"
    send_file Rails.public_path.join("index.html"), type: "text/html", disposition: "inline"
  end
end
