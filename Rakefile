# frozen_string_literal: true

require "rake/testtask"
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

desc "Run the release package smoke test"
task smoke: :test do
  sh "test/smoke/gem_install.sh"
end
