class Task
  def initialize(name, doc, block, dir)
    @name = name
    @doc = doc
    @block = block
    @dir = dir
  end

  def run(manager, *args)
    block_self = eval('self', @block.binding)
    context = TaskRunContext.new(manager, block_self)

    Dir.chdir(@dir) do
      context.instance_exec(*args, &@block)
    end
  end

  attr_accessor :name, :doc
end

class TaskNotFoundError < StandardError
  def initialize(name)
    @name = name
  end

  attr_reader :name
end

class DuplicateTaskError < StandardError
  def initialize(name)
    @name = name
  end

  attr_reader :name
end

class TaskManager
  def initialize
    @tasks = {}
  end

  def load(file)
    dir = File.dirname(file)
    context = TaskDefinitionContext.new(dir)
    context.instance_eval(File.read(file), file)
    @tasks.merge!(context.tasks)
  end

  def show_help
    puts 'Tasks:'
    width = @tasks.map { |name, task| name.length }.max
    @tasks.each do |name, task|
      space = ' ' * (width - name.length + 6)
      puts "  #{task.name}#{space}#{task.doc}"
    end
  end

  def run_task(name, *args)
    task = @tasks[name.to_s.downcase]
    if task.nil?
      raise TaskNotFoundError.new(name)
    end

    task.run(self, *args)
  end
end

class TaskDefinitionContext
  def initialize(dir)
    @tasks = {}
    @doc = nil
    @dir = dir
  end

  def doc(doc)
    @doc = doc
  end

  def run(name, &block)
    key = name.to_s.downcase

    if @tasks.include?(key)
      raise DuplicateTaskError.new(name)
    end

    @tasks[key] = Task.new(name.to_s, @doc, block, @dir)
    @doc = nil
  end

  attr_accessor :tasks
end

class TaskRunContext
  def initialize(manager, block_self)
    @manager = manager
    @self = block_self
  end

  def run(name, *args)
    @manager.run_task(name, *args)
  end

  def method_missing(method, *args, &block)
    @self.send(method, *args, &block)
  end
end

def find_runfile
  previous = nil
  dir = Dir.pwd
  while dir != previous
    runfile = File.join(dir, 'Runfile')
    return runfile.gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR) if File.exist?(runfile)
    previous = dir
    dir = File.expand_path(File.join(dir, '..'))
  end

  return nil
end

runfile = find_runfile
if runfile.nil?
  $stderr.puts "No Runfile found."
  exit 1
end

begin
  manager = TaskManager.new
  manager.load(runfile)

  task_name = ARGV[0]
  if !task_name
    manager.show_help
  else
    # Clear ARGV to avoid interference with `gets`:
    # http://ruby-doc.org/core-2.1.5/Kernel.html#method-i-gets
    args = ARGV[1...ARGV.length]
    ARGV.clear
    manager.run_task(task_name, *args)
  end
rescue TaskNotFoundError => e
  puts "Task '#{e.name}' not found."
  exit 1
rescue DuplicateTaskError => e
  puts "Task '#{e.name}' is already defined."
  exit 1
rescue Interrupt => e
  # Ignore interrupt and exit.
end
