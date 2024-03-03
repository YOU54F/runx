#!env ruby

project = 'runx'

version = `git tag`.lines.last.strip
if !version
  puts 'Version not found.'
  exit 1
end

puts ARGV[0]
if ARGV[0] == 'arm64'
  ARCH = 'arm64'
else
  ARCH = 'amd64'
end
target = "#{project}-linux-#{ARCH}-#{version}"
system("docker build --platform=linux/#{ARCH} -t #{project} .") || fail
system("docker run --platform=linux/#{ARCH} -it #{project} /bin/bash -c '/src/build-linux.sh -a #{ARCH}'") || fail
id = `docker ps -l -q`.strip
system("docker cp #{id}:/src/#{project} ./#{target}") || fail
system("docker rm #{id}") || fail
system("docker run --platform=linux/#{ARCH} -it --rm -v #{Dir.pwd}/#{target}:/bin/#{project} golang:latest bash") || fail
system("docker rmi #{project}:latest") || fail
