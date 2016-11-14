require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require 'bcrypt'

configure do 
  enable :sessions
  set :session_secret, 'secret'
end

before do
  @root = File.expand_path(".." "/launchschool-CMS-project")
end

class PasswordDigester
  def self.encrypt(password)
    BCrypt::Password.create(password)
  end

  def self.check?(password, encrypted_password)
    BCrypt::Password.new(encrypted_password) == password
  end
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def recieve_user_credentials
  users = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yaml", __FILE__)
  else
    File.expand_path("../users.yaml", __FILE__)
  end
  YAML.load_file(users)
end

def determine_file_extention(file)
  content = File.read(file)
  case File.extname(file)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    erb markdown.render(File.read(file)) 
  end
end

def accepted_file_extension?(filename)
  [".txt", ".md", ".doc", ".yaml", ".xml", ".docx"].include? File.extname(filename)
end

def user_signed_in?
  session.key?(:user)
end

def require_user_signin
  unless user_signed_in?
    session[:failure] = "You must be signed in to do that."
    redirect "/users/signin"
  end
end

get "/"  do
  redirect "/users/signin"
end

# View all files
get "/home" do
  pattern = File.join(data_path, "*")

  allfiles = File.join("**", "/data", "*.{*}")
  array = Dir.glob(allfiles)
  new_array = []
  array.each do |x|
     new_array << File.basename(x)
  end

  @files = new_array 
  erb :home, layout: :layout
end

get "/users/signin" do
  redirect "/home" if session[:user] 
  erb :login, layout: :layout 
end

post "/users/signin" do
  users = recieve_user_credentials
  username = params[:username]
  password = params[:password]
  if users.key?(username) && PasswordDigester.check?(password, users[username])
    session[:user] = username
    session[:success] = "Welcome!"
    redirect "/home"
  else
    session[:failure] = "Invalid credentials"
    status 422
    erb :login
  end
end

post "/users/signout" do
  session.delete(:user)
  session[:success] = "You have been signed out."
  redirect "/users/signin"
end

get "/new" do
  require_user_signin
 erb :new, layout: :layout
end

post "/new" do
require_user_signin
  new_file = params[:newfile].to_s

  if new_file.size == 0
    session[:failure] = "A name is required"
    status 422
      erb :new
  elsif !(1..100).cover? new_file.strip.size
    session[:failure] = "A name between 1 and 100 characters is required"
    status 422
      erb :new
  elsif !accepted_file_extension?(new_file) 
    session[:failure] = "This file extension is not accepted"
    status 422
      erb :new
  else
    file_path = File.join(data_path, new_file)
    File.write(file_path, "")
    session[:success] = "#{params[:newfile]} has been created"
    redirect "/home" 
  end
end

#View selected file
get "/:file" do
  file_path = File.join(data_path, params[:file])

  if File.exist?(file_path)
    determine_file_extention(file_path)
  else
    file_path = File.basename(file_path)
    session[:failure] = "#{file_path} does not exist" 
    redirect "/home"
  end  
end

# See file Edit Form
get "/:file/edit" do
  require_user_signin

  file_path = File.join(data_path, params[:file])
  @filecontent = File.read(file_path)
  @file_name = File.basename(file_path)
  erb :edit, layout: :layout
end

# Make Edits to file
post "/:file" do
  require_user_signin
  file_path = File.join(data_path, params[:file])
  @file_name= File.basename(file_path)

  File.write(file_path, params[:content])
  
  session[:success] = "#{@file_name} has been updated"
  redirect "/home" 
end

post "/:file/delete" do
  require_user_signin
  @file_name = params[:file].to_s
  filepath = File.join(data_path, params[:file])
  File.delete(filepath)

  session[:success] = "#{params[:file]} has been deleted"
  redirect "/home"
end

get "/:file/duplicate" do
  require_user_signin
  erb :copy layout: :layout
end

post "/:file/duplicate" do
  require_user_signin
  File.write(data_path, params[:newfilename])
  session[:success] = "#{params[:file]} has been duplicated"
end

