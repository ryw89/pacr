#!/usr/bin/env ruby
# coding: utf-8

require 'nokogiri'
require 'open-uri'

# Create an Arch Linux PKGBUILD file from a CRAN package name
class CreatePkgBuild
  def initialize(pkg)
    @pkg = pkg
    begin
    url = "https://cran.r-project.org/web/packages/#{@pkg}/index.html"
    doc = Nokogiri::HTML(open(url))
    rescue OpenURI::HTTPError => error
      response = error.io
      puts(response.status.join(' '))
      abort('Exiting pacr.')
    end

    # Text contains basic package description
    @cran_page_text = doc.at('body').text

    # Get main table on page containing most CRAN package info
    @cran_page_table = []
    table = doc.at('table')
    table.search('tr').each do |tr|
      cells = tr.search('th, td')
      # Newlines present in table cells, at least as parsed by
      # nokogiri.
      @cran_page_table.push(cells.text.gsub("\n", ""))
    end

    @cran_page_table = @cran_page_table.join("\n")

  end

  # Parse CRAN page for needed info.
  def cran_page_parse
    # Create 'pkgname' field for PKGBUILD
    @arch_pkgname = "r-#{@pkg}".downcase

    # Create 'pkgver' field for PKGBUILD
    # PKGBUILD guidelines do not allow '-' in version number, so
    # replace with underscore
    @cranver = @cran_page_table.split("Version:")[1].split("\n")[0]
    @arch_pkgver = @cranver.gsub('-', '_')

    # Create 'pkgdesc' field for PKGBUILD
    # Note, however, that this default description may not meet Arch
    # PKGBUILD guidelines.
    @arch_pkgdesc = @cran_page_text.split("#{@pkg}:")[1].split("\n")[0].strip

    # Create 'url' field for PKGBUILD
    @arch_url = "https://cran.r-project.org/package=#{@pkg}"

    # Create 'arch' field for PKGBUILD
    @arch_arch = "'i686' 'x86_64'"

    # Create 'license' field for PKGBUILD
    license = @cran_page_table.split("License:")[1].split("\n")[0]

    # Remove explanatory license notes inside square brackets
    # and links to license files sometimes found on CRAN 
    license.gsub!(/\[.*?\]/, "")
    license.gsub!("+ file LICENSE", "")
    license = license.split("|")  # CRAN seperates licenses by |
    license = license.map do |x| x.strip end
    license = license.map do |x| "'#{x}'" end
    @arch_license = license.join(' ')

    # Create 'depends' field for PKGBUILD
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

    @arch_depends = []
    dependencies.each do |dependency|
      arch_depend = dependency.split(' ')[0]

      # Dependency should be R package if not R itself, so prepend r-
      # for Arch package name, as per official guidelines
      arch_depend = "r-#{arch_depend}" unless arch_depend == 'R'
      arch_depend.downcase!

      version = dependency[/\((.*?)\)/m, 1]  # Regex between parentheses

      # PKGBUILD guidelines do not allow '-' in version number, so
      # replace with underscore
      version.gsub!('-', '_') unless version.nil?
      arch_depend = "#{arch_depend}#{version}"

      replacements = [['≥', '>='], ['≤', '<='], [' ', '']]
      replacements.each do |replacement|
        arch_depend.gsub!(replacement[0], replacement[1])
      end

      arch_depend = "'#{arch_depend}'"
      @arch_depends.push(arch_depend)
      
    end

    unless sysreqs.nil?
      sysreqs.each do |sysreq|
        sysreq.gsub!(/\(.*?\)/, "")
        sysreq = sysreq.strip
        sysreq = sysreq.downcase
        sysreq = "'#{sysreq}'"
        @arch_depends.push(sysreq)
      end
    end

    @arch_depends = @arch_depends.join(' ')

    optdepends = @cran_page_table.split("Suggests:")[1]
    optdepends = optdepends.split("\n")[0] unless optdepends.nil?
    optdepends = optdepends.split(', ') unless optdepends.nil?

    @arch_optdepends = []
    if optdepends.nil?
      @arch_optdepends = ''
    else
      optdepends.each do |dependency|
        arch_optdepend = dependency.split(' ')[0]
        arch_optdepend.downcase!

        # Dependency should be R package if not R itself, so prepend r-
        # for Arch package name, as per official guidelines
        arch_optdepend = "r-#{arch_optdepend}" unless arch_optdepend == 'R'
        arch_optdepend.downcase!

        # Regex between parentheses
        version = dependency[/\((.*?)\)/m, 1] 
  
        # PKGBUILD guidelines do not allow '-' in version number, so
        # replace with underscore
        version.gsub!('-', '_') unless version.nil?
        arch_optdepend = "#{arch_optdepend}#{version}"
  
        replacements = [['≥', '>='], ['≤', '<='], [' ', '']]
        replacements.each do |replacement|
          arch_optdepend.gsub!(replacement[0], replacement[1])
        end
  
        arch_optdepend = "'#{arch_optdepend}'"
        @arch_optdepends.push(arch_optdepend)

      end

      @arch_optdepends = @arch_optdepends.join(' ')

    end
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
arch=('i686' 'x86_64')
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
pkg = ARGV[0]
pkgbuild = CreatePkgBuild.new(pkg)
pkgbuild.cran_page_parse
pkgbuild.fill_pkgbuild_template
