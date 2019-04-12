#!/usr/bin/env ruby
# coding: utf-8

require 'bundler/setup'
require 'nokogiri'
require 'open-uri'
require 'yaml'

# Create an Arch Linux PKGBUILD file from a CRAN package name
class CreatePkgBuild
  def initialize(pkg, config)
    @pkg = pkg
    @config = config

    # Downcase case all 'override' keys to later allow for case
    # insenstivity of these keys (e.g., R2jags key is equivalent to
    # r2jags).
    @config['override'] = @config['override'].transform_keys(&:downcase)

    begin
      url = "https://cran.r-project.org/web/packages/#{@pkg}/index.html"
      @doc = Nokogiri::HTML(open(url))
    rescue OpenURI::HTTPError => error
      response = error.io
      abort("#{response.status.join(' ')}\nExiting pacr.")
    end
  end

  def get_cran_text_and_table
    # Text contains basic package description
    @cran_page_text = @doc.at('body').text

    # Get main table on page containing most CRAN package info
    @cran_page_table = []
    table = @doc.at('table')
    table.search('tr').each do |tr|
      cells = tr.search('th, td')
      # Newlines present in table cells, at least as parsed by
      # nokogiri.
      @cran_page_table.push(cells.text.gsub("\n", ''))
    end
    @cran_page_table = @cran_page_table.join("\n")
  end

  # Parse array of dependencies, making Arch PKGBUILD-friendly names
  # and versions
  def dependency_parse(dep_array)
    # Get list of packages not to be counted as dependencies from
    # config
    arch_depends_array = []
    dep_array.each do |dependency|
      arch_depend = dependency.split(' ')[0]

      # Dependency should be R package if not R itself, so prepend r-
      # for Arch package name, as per official guidelines
      arch_depend = "r-#{arch_depend}" unless arch_depend == 'R'
      arch_depend.downcase!

      # Version between parentheses on CRAN
      version = dependency[/\((.*?)\)/m, 1]

      # PKGBUILD guidelines do not allow '-' in version number,
      # replace with underscore
      version.gsub!('-', '_') unless version.nil?
      arch_depend = "#{arch_depend}#{version}"

      replacements = [['≥', '>='], ['≤', '<='], [' ', '']]
      replacements.each do |replacement|
        arch_depend.gsub!(replacement[0], replacement[1])
      end

      arch_depends_array.push(arch_depend)
    end
    return(arch_depends_array)
  end

  # Filter out non-dependencies
  def rm_non_deps(arch_depends_array)
    notdepend = @config['notdepend']
    arch_depends_array.reject! { |x| notdepend.include? x }
    return(arch_depends_array)
  end

  # Remove duplicate dependencies, favoring higher versions
  def rm_dup_deps(dep_array)
    raw_array = dep_array.dup

    dep_array.map! { |x| x.gsub('<', '') }
    dep_array.map! { |x| x.gsub('>', '') }

    pkg_names = dep_array.map { |x| x.split('=')[0] }

    pkg_vers = []
    dep_array.each do |dep|
      if dep.include?('=')
        pkg_vers.push(dep.split('=')[1])
      else
        # Arbitrary negative number for version comparison of
        # non-versioned dependencies
        pkg_vers.push(-1)
      end
    end

    no_dup_dep_names = []
    no_dup_dep_vers  = []
    no_dup_dep_out = []
    pkg_names.zip(pkg_vers, raw_array).each do |name, ver, raw_pkg_str|
      if ver.to_f < 0
        ver_str = ''
      else
        ver_str = ver
      end

      # Add dependency to no_dup_array if not already present. (It
      # will be removed later if a higher version of the same library
      # is found.)
      if not no_dup_dep_names.include?(name)
        no_dup_dep_names.push(name)
        no_dup_dep_vers.push(ver_str)
        no_dup_dep_out.push(raw_pkg_str)
      else
        # No need to compare if no version; it cannot be a greater
        # version than what's already in the array, by definition
        next if ver_str == ''

        # Get version of same-named dependency already in array
        name_match_index = no_dup_dep_names.find_index(name)
        ver_already_in_array = no_dup_dep_vers[name_match_index]

        if ver.to_f > ver_already_in_array.to_f
          no_dup_dep_names.push(name)
          no_dup_dep_vers.push(ver_str)
          no_dup_dep_out.push(raw_pkg_str)

          no_dup_dep_names.delete_at(name_match_index)
          no_dup_dep_vers.delete_at(name_match_index)
          no_dup_dep_out.delete_at(name_match_index)
        end
      end
    end
    return(no_dup_dep_out)
  end

  # # Create 'pkgname' field for PKGBUILD
  def arch_pkgname
    @arch_pkgname = "r-#{@pkg}".downcase
  end

  # Create 'pkgver' field for PKGBUILD
  def arch_pkgver
    # PKGBUILD guidelines do not allow '-' in version number, so
    # replace with underscore
    @cranver = @cran_page_table.split('Version:')[1].split("\n")[0]
    @arch_pkgver = @cranver.gsub('-', '_')
  end

  # Create 'pkgdesc' field for PKGBUILD
  def arch_pkgdesc
    # Note, however, that this default description may not meet Arch
    # PKGBUILD guidelines.
    @arch_pkgdesc = @cran_page_text.split("#{@pkg}:")[1].split("\n")[0].strip
    @arch_pkgdesc = @arch_pkgdesc.gsub(/.$/, '')
  end

  # Create 'url' field for PKGBUILD
  def arch_url
    @arch_url = "https://cran.r-project.org/package=#{@pkg}"
  end

  # Create 'arch' field for PKGBUILD
  def arch_arch
    arch = @cran_page_table.split("NeedsCompilation:")[1].split("\n")[0]

    if arch.nil?
      @arch_arch = "'any'"
      return
    end

    if arch.downcase.include?('yes')
      @arch_arch = "'i686' 'x86_64'"
    else
      @arch_arch = "'any'"
    end
  end

  # Create 'license' field for PKGBUILD
  def arch_license
    license = @cran_page_table.split("License:")[1].split("\n")[0]

    # Remove explanatory license notes inside square brackets
    # and links to license files sometimes found on CRAN 
    license.gsub!(/\[.*?\]/, '')

    # Remove CRAN links to license files
    license.gsub!('file LICENSE', '')
    license.gsub!('+', '')

    # CRAN seperates licenses by |
    license = license.split('|')

    license = license.map { |x| x.strip }
    license.reject! { |x| x.nil? || x.empty? }
    license = license.map { |x| "'#{x}'" }
    @arch_license = license.join(' ')
  end

  # Create 'depends' field for PKGBUILD
  def arch_depends
    depends   = @cran_page_table.split("Depends:")[1]
    depends   = depends.split("\n")[0] unless depends.nil?
    depends   = depends.split(', ') unless depends.nil?

    imports   = @cran_page_table.split("Imports:")[1]
    imports   = imports.split("\n")[0] unless imports.nil?
    imports   = imports.split(', ') unless imports.nil?

    linkingto = @cran_page_table.split("LinkingTo:")[1]
    linkingto = linkingto.split("\n")[0] unless linkingto.nil?
    linkingto = linkingto.split(', ') unless linkingto.nil?

    sysreqs   = @cran_page_table.split("SystemRequirements:")[1]
    sysreqs   = sysreqs.split("\n")[0] unless sysreqs.nil?
    sysreqs   = sysreqs.split(', ') unless sysreqs.nil?

    # sysreqs is handled its own way, so we won't add it to this
    # array.
    dependencies = [depends, imports, linkingto].reject do |x|
      x.nil? || x.empty?
    end
    dependencies = dependencies.flatten
    @arch_depends = dependency_parse(dependencies)

    # Remove explanatory notes about system requirements sometimes
    # found in parenthenses on CRAN
    unless sysreqs.nil?
      sysreqs.each do |sysreq|
        sysreq.gsub!(/\(.*?\)/, '')

        if sysreq.split.length > 1
          STDERR.puts("Warning: '#{sysreq}' does not appear to be a \
valid depdendency, not adding to PKGBUILD.")
          next
        end

        sysreq = sysreq.strip
        sysreq = sysreq.downcase
        @arch_depends.push(sysreq)
      end
    end

    # Remove duplicates if they exist
    @arch_depends = rm_dup_deps(@arch_depends)

    # Remove non-dependencies
    @arch_depends = rm_non_deps(@arch_depends)

    # Apostrophes for PKGBUILD
    @arch_depends.map! { |x| "'#{x}'" }

    @arch_depends = @arch_depends.join(' ')
  end

  # Create 'optdepends' field for PKGBUILD
  def arch_optdepends
    optdepends = @cran_page_table.split('Suggests:')[1]
    optdepends = optdepends.split("\n")[0] unless optdepends.nil?
    optdepends = optdepends.split(', ') unless optdepends.nil?

    @arch_optdepends = []
    if optdepends.nil?
      @arch_optdepends = ''
    else
      @arch_optdepends = dependency_parse(optdepends)
      @arch_optdepends = rm_dup_deps(@arch_optdepends)
      @arch_optdepends = rm_non_deps(@arch_optdepends)
      @arch_optdepends.map! { |x| "'#{x}'" }
      @arch_optdepends = @arch_optdepends.join(' ')
    end
  end

  # Override fields of PKGBUILD, as specified in config.yaml
  def override(pkgbuild_field, original_val)
    # For case insensitivity. Recall that keys from config.yaml
    # were all downcased as well.
    downcased_pkgname = @pkg.downcase

    if @config['override'][downcased_pkgname].nil?
      return(original_val)
    else
      override = @config['override'][downcased_pkgname]
    end

    if override[pkgbuild_field].downcase == 'null'
      return('')
    end

    if override[pkgbuild_field].nil? || override[pkgbuild_field].empty?
      return(original_val)
    end

    return(override[pkgbuild_field])

  end

  # Wrapper around override method for all PKGBUILD fields
  def override_all
    @arch_pkgname    = override('pkgname', @arch_pkgname)
    @arch_pkgver     = override('pkgver', @arch_pkgver)
    @arch_pkgdesc    = override('pkgdesc', @arch_pkgdesc)
    @arch_url        = override('url', @arch_url)
    @arch_arch       = override('arch', @arch_arch)
    @arch_license    = override('license', @arch_license)
    @arch_depends    = override('depends', @arch_depends)
    @arch_optdepends = override('optdepends', @arch_optdepends)
  end
  
  # Fill template from variables and print to stdout
  def fill_pkgbuild_template
    pkgbuild = "# Generated by pacr: github.com/ryw89/pacr
_cranname=#{@pkg}
_cranver=#{@cranver}
pkgname=#{@arch_pkgname}
pkgver=#{@arch_pkgver}
pkgrel=1
pkgdesc=\"#{@arch_pkgdesc}\"
url=\"https://cran.r-project.org/package=#{@pkg}\"
arch=(#{@arch_arch})
license=(#{@arch_license})
depends=(#{@arch_depends})
optdepends=(#{@arch_optdepends})
source=(\"http://cran.r-project.org/src/contrib/${_cranname}_${_cranver}.tar.gz\")
md5sums=('SKIP')
package() {
   mkdir -p ${pkgdir}/usr/lib/R/library
   cd ${srcdir}
   R CMD INSTALL ${_cranname} -l ${pkgdir}/usr/lib/R/library
}"

    puts(pkgbuild)
  end
end

# Run script
if ARGV.length < 1
  abort('No R package specified.')
end

# Load config file
if (File.exist?('./config.yaml'))
  config = YAML.load_file('./config.yaml')
elsif (File.exist?('~/.config/pacr/config.yaml'))
  config = YAML.load_file('~/.config/pacr/config.yaml')
elsif (File.exist?('/usr/share/pacr/config.yaml'))
  config = YAML.load_file('/usr/share/pacr/config.yaml')
else
  STDERR.puts("Warning: No config file found at \
/usr/share/pacr/config.yaml or ~/.config/pacr/config.yaml.")
  config = {"notdepend": [] }
end

pkg = ARGV[0]
pkgbuild = CreatePkgBuild.new(pkg, config)
pkgbuild.get_cran_text_and_table
pkgbuild.arch_pkgname
pkgbuild.arch_pkgver
pkgbuild.arch_pkgdesc
pkgbuild.arch_url
pkgbuild.arch_arch
pkgbuild.arch_license
pkgbuild.arch_depends
pkgbuild.arch_optdepends
pkgbuild.override_all
pkgbuild.fill_pkgbuild_template
