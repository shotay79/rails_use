namespace :railsroutes2aspida do
  desc 'Generate aspida files from Rails routes'
  task execute: :environment do
    RailsUse::Railsroutes2aspida.execute
  end
end
