require_relative 'docker_service'

module Dory
  class Dnsmasq
    extend Dory::DockerService

    @@first_attempt_failed = false

    def self.run_preconditions
      puts "[DEBUG] dnsmasq service running preconditions" if Dory::Config.debug?

      # we don't want to hassle the user with checking the port unless necessary
      if @@first_attempt_failed
        puts "[DEBUG] First attempt failed.  Checking port 53" if Dory::Config.debug?
        listener_list = self.check_port(53)
        unless listener_list.empty?
          return self.offer_to_kill(listener_list)
        end
        return false
      else
        puts "[DEBUG] Skipping preconditions on first run" if Dory::Config.debug?
        return true
      end
    end

    def self.handle_error(command_output)
      puts "[DEBUG] handling dnsmasq start error" if Dory::Config.debug?
      # If we've already tried to handle failure, prevent infinite recursion
      if @@first_attempt_failed
        puts "[DEBUG] Attempt to kill conflicting service failed" if Dory::Config.debug?
        return false
      else
        puts "[DEBUG] First attempt to start dnsmasq failed. There is probably a conflicting service present" if Dory::Config.debug?
        @@first_attempt_failed = true
        self.start(handle_error: false)
      end
    end

    def self.dnsmasq_image_name
      'freedomben/dory-dnsmasq'
    end

    def self.container_name
      Dory::Config.settings[:dory][:dnsmasq][:container_name]
    end

    def self.domain
      Dory::Config.settings[:dory][:dnsmasq][:domain]
    end

    def self.addr
      Dory::Config.settings[:dory][:dnsmasq][:address]
    end

    def self.run_command(domain = self.domain, addr = self.addr)
      "docker run -d -p 53:53/tcp -p 53:53/udp --name=#{Shellwords.escape(self.container_name)} " \
      "--cap-add=NET_ADMIN #{Shellwords.escape(self.dnsmasq_image_name)} " \
      "#{Shellwords.escape(domain)} #{Shellwords.escape(addr)}"
    end

    def self.check_port(port_num)
      puts "Requesting sudo to check if something is bound to port 53".green
      ret = Sh.run_command('sudo lsof -i :53')
      return [] unless ret.success?

      list = ret.stdout.split("\n")
      list.shift  # get rid of the column headers
      list.map! do |process|
        command, pid, user, fd, type, device, size, node, name = process.split(/\s+/)
        OpenStruct.new({
          command: command,
          pid: pid,
          user: user,
          fd: fd,
          type: type,
          device: device,
          size: size,
          node: node,
          name: name
        })
      end
    end

    def self.offer_to_kill(listener_list, answer: nil)
      listener_list.each do |process|
        puts "Process '#{process.command}' with PID '#{process.pid}' is listening on #{process.node} port 53."
      end
      pids = listener_list.uniq(&:pid).map(&:pid)
      pidstr = pids.join(' and ')
      print "This interferes with Dory's dnsmasq container.  Would you like me to kill PID #{pidstr}? (Y/N): "
      conf = answer ? answer : STDIN.gets.chomp
      if conf =~ /y/i
        puts "Requesting sudo to kill PID #{pidstr}"
        return Sh.run_command("sudo kill #{pids.join(' ')}").success?
      else
        puts "OK, not killing PID #{pidstr}.  Please kill manually and try starting dory again.".red
        return false
      end
    end
  end
end
