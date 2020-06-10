require 'sinatra'
require 'json'
require 'redis'
require 'octokit'

redis = Redis.new(url: ENV['REDIS_URL'])
octokit = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])

get '/' do
  'ok'
end

post '/webhook' do
  logger.info "[params] #{params.inspect}"
  subject = params['subject'].to_s
  body    = params['body'].to_s

  # Do nothing unless reply
  return unless subject.to_s.match(/^Re:/)

  # Extract feedback_id from subject
  feedback_id = subject.scan(/\(FB-(\d+)\)/).flatten.first
  return unless feedback_id

  # Extract feedback content from Email body
  feedback_content = body.gsub(/\R/, "\n").split(/\d{4}.\d{1,2}.\d{1,2}.+:$/).first.strip

  # Get issue number
  redis_key = "feedbacks:#{feedback_id}:issue_number"
  issue_number = redis.get(redis_key)

  unless issue_number
    query = "[FB-#{feedback_id}] in:title repo:#{ENV['REPO']}"
    query += " author:#{ENV['AUTHOR']}" if ENV['AUTHOR']

    issue = octokit.search_issues(query, sort: 'created', order: 'desc').items.first

    if issue
      issue_number = issue.number
      redis.set(redis_key, issue_number)
    else
      logger.error "[ERROR] GitHub Issue not found for query: #{query}"
      return
    end
  end

  # Add comment on the issue
  octokit.add_comment(ENV['REPO'], issue_number, "feedback-sync:\n\n#{feedback_content}")

  logger.info '[github comment] done'
end
