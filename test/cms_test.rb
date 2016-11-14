ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"
require_relative "../cms"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def app
    Sinatra::Application
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end


  def test_home
    create_document "about.md"
    create_document "changes.txt"
    
    get "/home",  {}, admin_session
    
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_history
    create_document "history.txt", "Ruby 0.95 released"

    get "/history.txt",  {}, admin_session
    
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Ruby 0.95 released"
  end

  def test_file_not_exist
    get "/not_a_file.ext",  {}, admin_session
    assert_equal 302, last_response.status
    assert_includes "not_a_file.ext does not exist", session[:failure]
  end

  def test_viewing_markdown_document
    create_document "about.md", "#Markdown: Syntax"
    get "/about.md",  {}, admin_session

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Markdown: Syntax</h1>"
  end

  def test_editing_document
    create_document "changes.txt"
    get "/changes.txt/edit",  {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

   def test_editing_document_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:failure]
  end

  def test_updating_document
    post "/changes.txt",  {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_includes "changes.txt has been updated", session[:success]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_updating_document_signed_out
    post "/changes.txt", {content: "new content"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:failure]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_new_document_form_signed_out
    get "/new"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:failure]
  end

  def test_create_new_document
    post "/new",  {newfile: "test.txt"}, admin_session
    assert_equal 302, last_response.status

    assert_includes "test.txt has been created", session[:success]

    get "/home"
    assert_includes last_response.body, "test.txt"
  end

  def test_create_new_document_signed_out
    post "/new", {newfile: "test.txt"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:failure]
  end

   def test_create_new_document_without_filename
    post "/new",  {newfile: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes  last_response.body,'A name is required'
  end

  def test_create_new_document_without_extension
    post "/new",  {newfile: "txt"}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "This file extension is not accepted"
  end

  def test_create_new_document_without_letters
    post "/new",  {newfile: "   "}, admin_session
    assert_equal 422, last_response.status
    assert_includes  last_response.body,'A name between 1 and 100 characters is required'
  end

  def test_delete_document
    create_document ("test.txt")

    post "/test.txt/delete",  {}, admin_session

    assert_equal 302, last_response.status

    assert_equal "test.txt has been deleted", session[:success]

    get "/home"
    refute_includes last_response.body, %q(href="/test.txt")
  end

  def test_deleting_document_signed_out
    create_document("test.txt")

    post "/test.txt"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:failure]
  end

  def test_login_site
    get "/users/signin"

    assert_equal 200, last_response.status

    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_login
    post "/users/signin", username: "admin", password: "secret"

    assert_equal 302, last_response.status

    assert_includes "Welcome!", session[:success]
    assert_includes "Signed in as admin", session[:user]
    get last_response["Location"]

    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_bad_credentials
    post "/users/signin", username: "XxhackerxX", password: "shady4days"
    assert_equal 422, last_response.status
    assert_equal nil, session[:user]
    assert_includes last_response.body, "Invalid credentials"
  end

  def test_logout
    get "/users/signin", {}, admin_session

    post "/users/signout"
    get last_response["Location"]

    assert_equal nil, session[:user]
    assert_includes last_response.body, "You have been signed out."
    assert_includes last_response.body, "Sign In"
  end

  if $0 == __FILE__
  password = ARGV.shift

  encrypted = PasswordDigester.encrypt password

  success = PasswordDigester.check? password, encrypted

  puts encrypted, success
end
end