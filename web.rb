require 'bundler/setup'
require 'sinatra'
require 'net/https'
require 'json'
require 'haml'
require 'sinatra/config_file'
require 'awesome_print'

config_file 'config/config.yml'

# add in basic auth using env variables
helpers do
  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    halt 401, "Not authorized\n"
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == [ENV['ADMIN_USER'], ENV['ADMIN_PASS']]
  end
end

get '/' do
  protected!

  @project = params["project"]? params["project"] : "pm"
  @grouping = params["group"]? params["group"] : "roadmap_group"

  @jiras = get_roadmap(@project)
  @r_items = []
  scrum_teams = []

  if(@jiras['issues'])
    @jiras['issues'].each_with_index {|jira, i|
      @r_item = {}

      if(jira['fields'])

        #puts 'JIRA CF: ' + jira['fields'].to_s
        if jira['fields']['customfield_12151'].nil?
          roadmap_group = "Unset"
        else
          roadmap_group = jira['fields']['customfield_12151']['value']
        end

        if jira['fields']['customfield_11850'].nil?
          scrum_team = "Unset"
        else
          scrum_team = jira['fields']['customfield_11850']['value']
        end
        scrum_teams << scrum_team unless scrum_teams.include?(scrum_team)
        sti = scrum_teams.index(scrum_team)+1
        if scrum_team == "Unset"
          sti = 99
        elsif scrum_team.include?("Roadmap")
          sti = 98
        end
        scrum_team = "#{sti}. #{scrum_team}"

        if jira['fields']['customfield_10003'].nil?
          points = 0;
        else
          points = jira['fields']['customfield_10003']
        end

        if jira['fields']['priority'].nil?
          priority = nil;
        else
          priority = jira['fields']['priority']['name']
          priority_image = jira['fields']['priority']['iconUrl']
        end


        @r_item['content'] = jira['fields']['summary']
        @r_item['start'] = Time.parse(jira['fields']['customfield_11950'])
        @r_item['end'] = Time.parse(jira['fields']['customfield_11951'])
        @r_item['scrum_team'] = scrum_team
        @r_item['jira_uri'] = 'https://' + settings.jira_host + '/browse/' + jira['key']
        @r_item['jira_description'] = jira['renderedFields']['description']
        @r_item['scrum_team_css'] = cssify(scrum_team)
        @r_item['jira_key'] = jira['key']
        @r_item['source'] = roadmap_group
        @r_item['points'] = points
        @r_item['priority'] = priority
        @r_item['priorityImage'] = priority_image

        if @grouping.eql? "scrum_team"
          @r_item['group'] = scrum_team
        else
          @r_item['group'] = roadmap_group
        end

        @r_items.push(@r_item)
      end
    }
  end

  haml :index, :locals => {:jiras => @r_items}
end

def cssify(input)
  input = input.tr( '^A-Za-z', '' )
  input = input.tr( 'A-Z', 'a-z' )

  return input
end

##
#
# Get the data from the JIRA server
#
##
def get_roadmap(project)

  @jira_epics = ''

  http = Net::HTTP.new(settings.jira_host, settings.jira_port)
  http.use_ssl = settings.use_ssl
  http.start do |http|
    req = Net::HTTP::Get.new(settings.jira_queries[project])

    # we make an HTTP basic auth by passing the
    # username and password
    req.basic_auth ENV['JIRA_USER'], ENV['JIRA_PASS']
    resp, data = http.request(req)
    #print "Resp: " + resp.code.to_s + "\n"
    #print "Data: " +  JSON.pretty_generate(JSON.parse(resp.body.to_s))

    @jira_epics = JSON.parse(resp.body.to_s)
  end

  return @jira_epics
end
