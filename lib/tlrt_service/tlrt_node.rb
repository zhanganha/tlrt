# Copyright (c) 2009-2011 VMware, Inc.
require "erb"
require "fileutils"
require "logger"
require "pp"
require "set"
require "timeout"

require "nats/client"
require "uuidtools"

require 'vcap/common'
require 'vcap/component'
require "tlrt_service/common"

module VCAP
  module Services
    module Tlrt
      class Node < VCAP::Services::Base::Node
      end
    end
  end
end

class VCAP::Services::Tlrt::Node

  include VCAP::Services::Tlrt::Common

  # FIXME only support rw currently

  # Max clients' connection number per instance
  MAX_CLIENTS = 500


  class ProvisionedService
    include DataMapper::Resource
    property :name,       String,   :key => true
    property :port,       Integer,  :unique => true
    # property plan is deprecated. The instances in one node have same plan.
    property :plan,       Integer, :required => true
    property :pid,        Integer
    property :memory,     Integer
    property :version,    String

    def listening?
      begin
        TCPSocket.open('localhost', port).close
        return true
      rescue => e
        return false
      end
    end

    def running?
      true
    end
    
  end

  def initialize(options)
    super(options)
    @base_dir = options[:base_dir]
    FileUtils.mkdir_p(@base_dir)
    @tlrt_path = options[:tlrt_path]
    @tlrt_shutdown_path = options[:tlrt_shutdown_path]
    @available_capacity = options[:capacity]
    @tlrt_log_dir = options[:mongod_log_dir]
    @local_db = options[:local_db]
    @free_ports = Set.new
    @free_ports_mutex = Mutex.new
    options[:port_range].each {|port| @free_ports << port}
    @max_clients = options[:max_clients] || MAX_CLIENTS

    @config_template = ERB.new(File.read(options[:config_template]))

  end
  
  def pre_send_announcement
    super
    start_db
    start_provisioned_instances 
  end

  def shutdown
   
  end

  def announcement
    @capacity_lock.synchronize do
      { :available_capacity => @capacity,
        :capacity_unit => capacity_unit }
    end
  end

  def all_instances_list
    ProvisionedService.all.map{|ps| ps["name"]}
  end

  def all_bindings_list
    list = []
    list
  end

  def provision(plan, credential = nil, version=nil)
    @logger.info("Provision request: plan=#{plan}")
    name = UUIDTools::UUID.random_create.to_s
    #port ="10240"
    provisioned_service           = ProvisionedService.new
    provisioned_service.name      = name
    provisioned_service.port      = fetch_port
    provisioned_service.plan      = 1
    provisioned_service.version   = version
    raise "Cannot save provision_service" unless provisioned_service.save


    # wait for tlrt to start
    sleep 0.5

    host = get_host
    response = {
      "hostname" => host,
      "host" => host,
      "port" => provisioned_service.port,
      "name" => provisioned_service.name
    }
    @logger.debug("Provision response: #{response}")
    return response
  rescue => e
    @logger.error("Error provision instance: #{e}")
    cleanup_service(provisioned_service)
    raise e
  end

  def unprovision(name, bindings)
    true
  end
 
  def stop_service
  end

  def cleanup_service(provisioned_service)
    true
  end

  def bind(name, bind_opts, credential = nil)

    provisioned_service = ProvisionedService.get(name)
    host = get_host
    # use default port of tlrt 10240
    port = "10240"
    response = {
      "hostname" => host,
      "host"     => host,
      "port"     => port,
      "name"     => provisioned_service.name,
    }

    @logger.debug("Bind response: #{response}")
    response
  end

  def unbind(credential)
    true
  end

  def restore(instance_id, backup_file)
    true
  end

  def disable_instance(service_credential, binding_credentials)
    true
  end

  def enable_instance(service_credential, binding_credentials)
    true
  end

  def dump_instance(service_credential, binding_credentials, dump_dir)
    true
  end

  def import_instance(service_credential, binding_credentials, dump_dir, plan)
    true
  end

  def update_instance(service_credential, binding_credentials)
  end

  def fetch_port(port=nil)
      port ||= @free_ports.first
      raise "port #{port} is already taken!" unless @free_ports.include?(port)
      @free_ports.delete(port)
      port
  end

  def varz_details
    varz = {}
    varz[:provisioned_instances] = []
    varz[:provisioned_instances_num] = 0
    varz[:max_capacity] = @max_capacity
    varz[:available_capacity] = @capacity
    varz[:instances] = {}
    ProvisionedService.all.each do |instance|
      varz[:provisioned_instances_num] += 1
    end
    varz
  rescue => e
    @logger.warn(e)
    {}
  end

  def start_instance(provisioned_service)
  end

  def start_db
    DataMapper.setup(:default, @local_db)
    DataMapper::auto_upgrade!
  end

  def start_provisioned_instances
    #delete the port already used
    ProvisionedService.all.each do |provisioned_service|
      @free_ports.delete(provisioned_service.port)
    end
  end
end

