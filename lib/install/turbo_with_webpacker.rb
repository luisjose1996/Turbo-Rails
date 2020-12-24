# Some Rails versions use commonJS(require) others use ESM(import).
TURBOLINKS_REGEX = /(import .* from "turbolinks".*\n|require\("turbolinks"\).*\n)/.freeze
RAILS_UJS_REGEX  = /(import .* from "@rails\/ujs".*\n|require\("@rails\/ujs"\).*\n)/.freeze

abort "❌ Webpacker not found. Exiting." unless defined?(Webpacker::Engine)

say "Install @hotwired/turbo-rails"
run "yarn add @hotwired/turbo-rails"
insert_into_file "#{Webpacker.config.source_entry_path}/application.js",
  "import { Turbo, cable } from \"@hotwired/turbo-rails\"\n", before: TURBOLINKS_REGEX

say "Turn off turbolinks"
gsub_file 'Gemfile', /gem 'turbolinks'.*/, ''
run "bin/bundle", capture: true
run "bin/yarn remove turbolinks"
gsub_file "#{Webpacker.config.source_entry_path}/application.js", TURBOLINKS_REGEX, ''
gsub_file "#{Webpacker.config.source_entry_path}/application.js", /Turbolinks.start.*\n/, ''

say "Turn off @rails/ujs"
run "bin/yarn remove @rails/ujs"
gsub_file "#{Webpacker.config.source_entry_path}/application.js", RAILS_UJS_REGEX, ''
gsub_file "#{Webpacker.config.source_entry_path}/application.js", /Rails.start.*\n/, ''

say "Enable redis in bundle"
uncomment_lines "Gemfile", %(gem 'redis')

say "Switch development cable to use redis"
gsub_file "config/cable.yml", /development:\n\s+adapter: async/, "development:\n  adapter: redis\n  url: redis://localhost:6379/1"

say "Turbo successfully installed 🎉 ⚡️", :green
