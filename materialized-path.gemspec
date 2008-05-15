# -*- mode: ruby -*-

require 'rake'

Gem::Specification.new do |spec|
  spec.name = 'materialized-path'
  spec.version = '0.0.1'
  spec.date = '2008-05-15'
  spec.summary = 'An ActsAs mixin implementing a set of trees (nested set) for ActiveRecord  '
  spec.email = 'and@prospectmarkets.com'
#  spec.homepage = 'http://github.com/mojombo/grit'
  spec.description = 'An ActsAs mixin implementing a set of trees (nested set) for ActiveRecord  '
  spec.has_rdoc = false
  spec.authors = ['Antony Donovan']
  spec.files = FileList[ 'README' ]
#  spec.test_files = [ '' ]
#  spec.rdoc_options = ['--main', 'README.txt']
#  spec.extra_rdoc_files = ['History.txt', 'Manifest.txt', 'README.txt']
  spec.add_dependency('activerecord', ['>= 2.0.2'])
end
