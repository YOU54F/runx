$:.unshift(File.join(__dir__, 'lib'))

require 'colorize'
require 'io/console'
require 'pathname'
require 'set'

class RunxError < StandardError
  def initialize(message)
    super(message)
  end
end

class Task
  def initialize(name, method, description, dir, source)
    @name = name
    @method = method
    @description = description
    @dir = dir
    @source = source
  end

  def run(*args, &block)
    if !Dir.exist?(@dir)
      raise RunxError.new("task #{@name}: directory not found: #{@dir}")
    end

    Dir.chdir(@dir) do
      $stderr.puts "[runx] in #{@dir}"
      @method.call(*args, &block)
    end
  end

  attr_accessor :name, :method, :description, :source
end

class SourceLocation
  def initialize(filename, line_number)
    @filename = filename
    @line_number = line_number
  end

  def self.from_frame(frame)
    if frame =~ /^(.*?):(\d+)/
      SourceLocation.new($1, $2.to_i)
    elsif frame =~ /^(.*?):/
      SourceLocation.new($1, nil)
    else
      SourceLocation.new(nil, nil)
    end
  end

  def to_s
    if @filename
      if @line_number
        "#{@filename}:#{@line_number}"
      else
        @filename
      end
    else
      '(unknown)'
    end
  end

  attr_accessor :filename, :line_number
end

class Import
  def initialize(dir, source)
    @absolute_dir = File.expand_path(dir).gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
    @source = source
  end

  attr_accessor :absolute_dir, :source
end

class TaskManager
  def initialize
    @runfiles = {}
    @filenames_seen = Set.new
    @tasks = {}
    @imports = []
    @common_dir_prefix = nil
  end

  def load(filename)
    load_runfile(filename)
    while @imports.any?
      import = @imports.pop
      begin
        filename = runfile_path(import.absolute_dir)
        load_runfile(filename)
      rescue RunxError => e
        raise RunxError.new("import from #{import.source}: #{e}")
      end
    end

    @runfiles.values.flatten.each do |task|
      copy = @tasks[task.name]
      if !copy.nil?
        raise RunxError.new("duplicate task '#{task.name}' defined at #{copy.source} and #{task.source}")
      end

      @tasks[task.name] = task
    end

    if @tasks.empty?
      raise RunxError.new('no tasks defined, see https://github.com/schmich/runx#usage')
    end

    dirs = @filenames_seen.map { |path| File.dirname(path) }
    @common_dir_prefix = common_dir_prefix(dirs)
  end

  def show_help
    $stderr.puts 'Tasks:'

    multifile = @runfiles.values.count > 1
    task_leader = multifile ? '    ' : '  '

    # Some consoles won't let you print on the last column without
    # an extra newline, so we avoid the last column entirely.
    _, console_width = IO.console.winsize
    console_width -= 1

    parameters = Hash[@tasks.values.map { |task|
      [task, format_parameters(task.method.parameters)]
    }]

    make_title = proc { |task, colorize|
      name = colorize ? task.name.cyan : task.name
      [name, parameters[task]].reject(&:empty?).join(' ')
    }

    task_width = @tasks.values.map { |task| make_title.call(task, false).length }.max
    task_pad = 5

    description_width = console_width - task_leader.length - task_width - task_pad
    description_leader = ' ' * (task_leader.length + task_width + task_pad)

    @runfiles.each do |filename, tasks|
      next if tasks.empty?

      $stderr.puts
      if multifile
        $stderr.puts "  #{relative_path(filename)}"
        $stderr.puts
      end

      tasks.each do |task|
        space = ' ' * (task_width - (make_title.call(task, false).length) + task_pad)
        $stderr.print "#{task_leader}#{make_title.call(task, true)}#{space}"

        description_lines = word_wrap(task.description, description_width)
        0.upto(description_lines.count - 1) do |i|
          $stderr.print description_leader if i > 0
          $stderr.puts description_lines[i]
        end
      end
    end
  end

  def task_defined?(name)
    !@tasks[name.to_s.downcase].nil?
  end

  def run_task(name, args)
    task = @tasks[name.to_s.downcase]
    raise RunxError.new("task '#{name}' not found") if task.nil?
    args = argv_to_args(args)
    task.run(*args)
  end

  private

  def word_wrap(string, width)
    lines = string.split("\n").flat_map { |part| word_wrap_line(part, width) }
    return lines.empty? ? [''] : lines
  end

  def word_wrap_line(string, width)
    return [string] if string.length <= width
    index = string.rindex(/\s/, width) || width
    left, right = string[0...index], string[index...string.length].lstrip
    return [left] + word_wrap_line(right, width)
  end

  def format_parameters(params)
    params.map { |param|
      type, name = param
      name = name.to_s.gsub(/_/, '-')
      if type == :rest
        "[#{name.upcase}...]"
      elsif type == :req
        name.upcase
      elsif type == :opt
        "[#{name.upcase}]"
      elsif type == :keyreq
        "--#{name} VALUE"
      elsif type == :key
        "[--#{name} VALUE]"
      end
    }.join(' ')
  end

  def argv_to_args(argv)
    named = {}
    positional = []
    name = nil

    argv.each do |arg|
      if name
        named[name] = arg
        name = nil
      elsif arg =~ /^--(.+?)(=(.*))?$/
        value = $3
        name = $1.gsub('-', '_').to_sym
        if value
          named[name] = value
          name = nil
        end
      else
        positional << arg
      end
    end

    if named.empty?
      positional
    else
      positional + [named]
    end
  end

  def common_dir_prefix(dirs)
    dirs.map { |dir|
      paths = []
      Pathname.new(dir).cleanpath.ascend { |path| paths << path }
      paths.reverse
    }.reduce { |acc, cur|
      acc.zip(cur).take_while { |l, r| l == r }.map(&:first)
    }.last.to_s
  end

  def relative_path(path)
    relative_path = Pathname.new(File.dirname(path)).relative_path_from(Pathname.new(@common_dir_prefix)).to_s
    relative_path = '' if relative_path == '.'

    common_parent = File.basename(@common_dir_prefix)
    return Pathname.new(File.join(common_parent, relative_path))
      .cleanpath.to_s
      .gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
  end

  def load_runfile(filename)
    if !File.exist?(filename)
      raise RunxError.new("#{filename} not found")
    end

    absolute_filename = File.expand_path(filename).gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
    absolute_dir = File.dirname(absolute_filename)

    # Do not load the same file twice.
    return if !@filenames_seen.add?(absolute_filename)

    Dir.chdir(absolute_dir) do
      runfile = Runfile.new(absolute_dir)
      context = RunfileContext.new(runfile)
      InstanceBinding.for(context).eval(File.read(absolute_filename), absolute_filename)
      @runfiles[absolute_filename] = runfile.tasks
      @imports += runfile.imports
    end
  end
end

module InstanceBinding
  def self.for(object)
    @object = object
    create
  end

  def self.create
    @object.instance_eval { binding }
  end
end

class RunfileContext
  def initialize(runfile)
    @_ = runfile
  end

  def import(dir)
    source = SourceLocation.from_frame(caller(1).first)
    @_.import(dir, source)
  end

  def task(description = '')
    source = SourceLocation.from_frame(caller(1).first)
    @_.task(description, source)
  end

  def singleton_method_added(id)
    source = SourceLocation.from_frame(caller(1).first)
    @_.method_added(id, self, source)
  end
end

class Runfile
  def initialize(dir)
    @tasks = []
    @imports = []
    @description = nil
    @task_source = nil
    @dir = dir
  end

  def import(dir, source)
    @imports << Import.new(dir, source)
  end

  def task(description, source)
    if !@task_source.nil?
      raise RunxError.new("task declared with no implementing method at #{@task_source}")
    end

    @task_source = source
    @description = description
  end

  def method_added(id, obj, source)
    return if @task_source.nil?
    @task_source = nil

    name = id.to_s
    method = obj.method(id)
    @tasks << Task.new(name, method, @description, @dir, source)
  end

  attr_accessor :tasks, :imports
end

def restore_env
  map = {
    'LD_LIBRARY_PATH' => 'RUNX_LD_LIBRARY_PATH',
    'DYLD_LIBRARY_PATH' => 'RUNX_DYLD_LIBRARY_PATH',
    'TERMINFO' => 'RUNX_TERMINFO',
    'SSL_CERT_DIR' => 'RUNX_SSL_CERT_DIR',
    'SSL_CERT_FILE' => 'RUNX_SSL_CERT_FILE',
    'RUBYOPT' => 'RUNX_RUBYOPT',
    'RUBYLIB' => 'RUNX_RUBYLIB',
    'GEM_HOME' => 'RUNX_GEM_HOME',
    'GEM_PATH' => 'RUNX_GEM_PATH'
  }

  map.each do |real, temp|
    orig = ENV[temp]
    if orig.nil? || orig.strip.empty?
      ENV.delete(real)
    else
      ENV[real] = orig.strip
    end
  end

  map.values.each do |temp|
    ENV.delete(temp)
  end
end

def runfile_path(dir)
  File.join(dir, 'Runfile.rb').gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
end

def find_runfile
  Pathname.getwd.ascend do |dir|
    runfile = runfile_path(dir)
    return runfile if File.exist?(runfile)
  end

  raise RunxError.new('no Runfile.rb found')
end

begin
  # Restore environment to match original.
  restore_env

  runfile = find_runfile
  manager = TaskManager.new
  manager.load(runfile)

  task_name = ARGV[0]

  is_help = ['-h', '--help', 'help'].include?(task_name)
  show_help = !task_name || (is_help && !manager.task_defined?(task_name))

  if show_help
    $stderr.puts "[runx] in #{File.dirname(runfile)}"
    $stderr.puts
    manager.show_help
  else
    # Clear ARGV to avoid interference with `gets`:
    # http://ruby-doc.org/core-2.1.5/Kernel.html#method-i-gets
    args = ARGV[1...ARGV.length]
    ARGV.clear

    manager.run_task(task_name, args)
  end
rescue RunxError => e
  $stderr.puts "[runx] error: #{e}"
  exit 1
rescue Interrupt => e
  # Ignore interrupt and exit.
end
