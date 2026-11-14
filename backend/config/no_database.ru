message = <<~HTML.freeze
  <!doctype html>
  <html lang="en">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Database configuration required</title>
    <main>
      <h1>Service is not configured</h1>
      <p>PostgreSQL is required to use this application. Set DATABASE_URL and restart the service.</p>
      <p>The booking API is unavailable until the database is configured.</p>
    </main>
  </html>
HTML

run lambda { |env|
  if env["PATH_INFO"] == "/"
    [ 200, { "content-type" => "text/html; charset=utf-8", "content-length" => message.bytesize.to_s }, [ message ] ]
  else
    [ 404, { "content-type" => "text/plain; charset=utf-8" }, [ "Not found" ] ]
  end
}
