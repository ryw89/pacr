#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'optparse'
require 'yaml'

def make_pkgbuild(pkgname, pacr_depcheck_path, pacr_pkgbuild_path, force)
  # Function for making directories and PKGBUILDs using pacr-pkgbuild.
  arch_pkgname = 'r-' + pkgname.downcase
  pkgbuild = `#{pacr_pkgbuild_path} #{pkgname}`

  if $?.exitstatus == 0
    begin
      Dir.mkdir(arch_pkgname)
    rescue Errno::EEXIST
      warn("Directory #{arch_pkgname} already exists, not creating.")
      return nil unless force == true
    end

    File.open("#{arch_pkgname}/PKGBUILD", 'w') { |file| file.write(pkgbuild) }
    puts("Wrote PKGBUILD for #{arch_pkgname}.")
  else
    warn("#{pacr_pkgbuild_path} #{pkgname} failed with exit status #{$?.exitstatus}.")
  end
end

def pkgbuild_dryrun(pkgname, pacr_depcheck_path, pacr_pkgbuild_path)
  # Dry run of pacr without writing a file.
  pkgbuild = `#{pacr_pkgbuild_path} #{pkgname}`
  pkgbuild
end

# Argument parsing
pkg = ''
recursive = true
force = false
dry_run = false

OptionParser.new do |opts|
  # Default banner is "Usage: #{opts.program_name} [options]".
  opts.banner += ' [arguments...]'
  opts.separator 'Generate PKGBUILDs for R packages on CRAN.'
  opts.version = '1.0'

  opts.on('-p', '--pkg PKG',
          'Name of R package on CRAN') { |arg| pkg = arg }
  opts.on('-n', 'Do not generate dependencies recursively') { recursive = false }
  opts.on('-f', 'Overwrite already-existing PKGBUILDs') { force = true }
  opts.on('-d', 'Dry run -- do not write any files') { dry_run = true }

  begin
    opts.parse!
  rescue OptionParser::ParseError => e
    warn(e)
    warn('(-h or --help will show valid options)')
    exit 1
  end
end

abort('No R package specified.') if pkg.empty?

# Main script
# Load config file
if File.exist?('./config.yaml')
  config = YAML.load_file('./config.yaml')
elsif File.exist?('~/.config/pacr/config.yaml')
  config = YAML.load_file('~/.config/pacr/config.yaml')
elsif File.exist?('/usr/share/pacr/config.yaml')
  config = YAML.load_file('/usr/share/pacr/config.yaml')
else
  warn("Warning: No config file found at \
/usr/share/pacr/config.yaml or ~/.config/pacr/config.yaml.")
  config = { "cranmirror": 1,
             "notdepend": [] }
end

# Check if pacr-depcheck and pacr-pkgbuild exist in $PATH. If not,
# we'll use the pacr-depcheck.r and pacr-pkgbuild.rb which should
# exist in the same directory as pacr.rb.
curdir = __dir__ + '/'

pacr_depcheck_path = `which pacr-depcheck 2>/dev/null`
pacr_pkgbuild_path = `which pacr-pkgbuild 2>/dev/null`

pacr_depcheck_path.strip!
pacr_pkgbuild_path.strip!

pacr_depcheck_path = curdir + 'pacr-depcheck.r' if pacr_depcheck_path.empty?
pacr_pkgbuild_path = curdir + 'pacr-pkgbuild.rb' if pacr_pkgbuild_path.empty?

# Get package dependencies using pacr-depcheck script.
pkg_deps = `#{pacr_depcheck_path} #{pkg} #{recursive} #{config['cranmirror']}`
pkg_deps = pkg_deps.split("\n")

# Remove package dependencies that are R base packages (e.g. MASS,
# lattice, etc.). We don't want to build Arch Linux PKGBUILDs for
# these.
notdepend = config['notdepend']
notdepend.map! { |x| x.split('r-')[1] }

pkg_deps_filtered = []
pkg_deps.each do |pkg_dep|
  pkg_deps_filtered.push(pkg_dep) unless notdepend.include? pkg_dep.downcase
end

# TODO: Argument flags with optparse.
# Want: recursive dependencies flag, force overwrite flag,
# dry run flag.

# Make PKGBUILD for main package
if dry_run == false
  make_pkgbuild(pkg, pacr_depcheck_path, pacr_pkgbuild_path, force)
else
  dry_run_res = pkgbuild_dryrun(pkg, pacr_depcheck_path, pacr_pkgbuild_path)
  if dry_run_res.empty?
    warn("pacr-pkgbuild returned no output for #{pkg}.")
  else
    puts("pacr-pkgbuild succeeded for #{pkg}.")
  end
end

# Loop through pkg_deps_filtered and make PKGBUILDs using
# pacr-pkgbuild.rb. Save files in new directories.
pkg_deps_filtered.each do |pkg_dep|
  if dry_run == false
    make_pkgbuild(pkg_dep, pacr_depcheck_path, pacr_pkgbuild_path, force)
  else
    dry_run_res = pkgbuild_dryrun(pkg_dep, pacr_depcheck_path, pacr_pkgbuild_path)
    if dry_run_res.empty?
      warn("pacr-pkgbuild returned no output for #{pkg_dep}.")
    else
      puts("pacr-pkgbuild succeeded for #{pkg_dep}.")
    end
  end
end
