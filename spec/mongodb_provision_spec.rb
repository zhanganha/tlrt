# Copyright (c) 2009-2011 VMware, Inc.
$:.unshift(File.dirname(__FILE__))
require "spec_helper"

describe "mongodb_node provision" do
  MAX_CONNECTION = 100

  before :all do
    EM.run do
      @opts = get_node_config()
      @logger = @opts[:logger]
      @node = Node.new(@opts)
      @node.max_clients = MAX_CONNECTION

      EM.add_timer(2) { @resp = @node.provision("free") }
      EM.add_timer(4) { EM.stop }
    end
  end

  it "should have valid response" do
    @resp.should_not be_nil
    puts @resp
    inst_name = @resp['name']
    inst_name.should_not be_nil
    inst_name.should_not == ""
  end

  it "should be able to connect to mongodb" do
    is_port_open?('127.0.0.1', @resp['port']).should be_true
  end

  it "should not allow unauthorized user to access the instance" do
    EM.run do
      begin
        conn = Mongo::Connection.new('localhost', @resp['port'])
        db = conn.db(@resp['db'])
        coll = db.collection('mongo_unit_test')
        coll.insert({'a' => 1})
        coll.count()
      rescue Exception => e
        @logger.debug e
      ensure
        conn.close if conn
      end
      e.should_not be_nil
      EM.stop
    end
  end

  it "should return varz" do
    EM.run do
      stats = nil
      10.times do
        stats = @node.varz_details
      end
      stats.should_not be_nil
      stats[:running_services].length.should > 0
      stats[:running_services][0]['name'].should_not be_nil
      stats[:running_services][0]['db'].should_not be_nil
      stats[:running_services][0]['overall']['connections']['current'].should == 1
      stats[:disk].should_not be_nil
      stats[:max_capacity].should > 0
      stats[:available_capacity].should > 0
      stats[:instances].length.should > 0
      EM.stop
    end
  end

  it "should ensure max connection number is configured in mongod" do
    EM.run do
      stats = @node.varz_details
      current = stats[:running_services][0]['overall']['connections']['current']
      available = stats[:running_services][0]['overall']['connections']['available']

      MAX_CONNECTION.should == current + available

      EM.stop
    end
  end

  it "should enforce no more than max connection to be accepted" do
    first_conn_refused = false
    max_conn_refused = false
    connections = []

    stats = @node.varz_details
    available = stats[:running_services][0]['overall']['connections']['available']

    # A issue here:
    # There are two socket connection used in each iteration of the following loop.
    #    1. One created in "Mongo::Connection.new". This one is temperory, it's closed when return from new.
    #       But this close is not a syncornized close. It doesn't wait the tcp close ack from mongod. So there
    #       are one connection occupied in server side in short time, this will cause the following connection
    #       fails when maxConn reached.
    #    2. The other socket connection created in "db.authenticate()", this socket is a persistent one.
    #
    #  So the solution here is when we meet a connection failure and maxConn reached, we insert a sleep after
    #  first connection close. So that client and mongod can sync the state.
    #
    retry_count = 20
    available.times do |i|
      begin
        conn = Mongo::Connection.new('localhost', @resp['port'])
        if first_conn_refused
          sleep 1
          first_conn_refused = false
        end
        db = conn.db(@resp['db'])
        auth = db.authenticate(@resp['username'], @resp['password'])
        connections << conn
      rescue Mongo::ConnectionFailure => e
        first_conn_refused = true
        retry_count -= 1
        retry if ( (i >= (available-1)) && (retry_count > 0))
      end
    end

    # max+1's connection should fail
    begin
      conn = Mongo::Connection.new('localhost', @resp['port'])
      db = conn.db(@resp['db'])
      auth = db.authenticate(@resp['username'], @resp['password'])
      connections << conn
    rescue Mongo::ConnectionFailure => e
      max_conn_refused = true
    end

    # Close connections
    connections.each do |c|
      c.close
    end

    # Some version of MongoDB might not ensure max connection.
    # For example, MongoDB 1.8 32bits, when set maxConns = 100, it only accepts
    # 99 connections.
    first_conn_refused.should be(false),
      'Some version of MongoDB might not ensure max connection'
    max_conn_refused.should == true
    connections.size.should == available
  end


  it "should allow authorized user to access the instance" do
    EM.run do
      begin
        conn = Mongo::Connection.new('localhost', @resp['port'])
        db = conn.db(@resp['db'])
        auth = db.authenticate(@resp['username'], @resp['password'])
        auth.should be_true
        coll = db.collection('mongo_unit_test')
        coll.insert({'a' => 1})
        coll.count().should == 1
      rescue => e
      ensure
        conn.close if conn
      end
      EM.stop
    end
  end

  it "should keep the result after node restart" do
    port_open_1 = nil
    port_open_2 = nil
    EM.run do
      EM.add_timer(0) { @node.shutdown }
      EM.add_timer(1) { port_open_1 = is_port_open?('127.0.0.1', @resp['port']) }
      EM.add_timer(2) { @node = Node.new(@opts) }
      EM.add_timer(3) { port_open_2 = is_port_open?('127.0.0.1', @resp['port']) }
      EM.add_timer(4) { EM.stop }
    end

    begin
      port_open_1.should be_false
      port_open_2.should be_true
      conn = Mongo::Connection.new('localhost', @resp['port'])
      db = conn.db(@resp['db'])
      auth = db.authenticate(@resp['username'], @resp['password'])
      auth.should be_true
      coll = db.collection('mongo_unit_test')
      coll.count().should == 1
    rescue => e
    ensure
      conn.close if conn
    end
  end

  it "should return error when unprovisioning a non-existed instance" do
    EM.run do
      e = nil
      begin
        @node.unprovision('no existed', [])
      rescue => e
      end
      e.should_not be_nil
      EM.stop
    end
  end

  it "should report error when admin users are deleted from mongodb" do
    EM.run do
      delete_admin(@resp)
      stats = @node.varz_details
      stats.should_not be_nil
      stats[:running_services].length.should > 0
      stats[:running_services][0]['db'].class.should == String
      stats[:running_services][0]['overall'].class.should == String
      EM.stop
    end
  end

  # unprovision here
  it "should be able to unprovision an existing instance" do
    EM.run do
      @node.unprovision(@resp['name'], [])

      e = nil
      begin
        conn = Mongo::Connection.new('localhost', @resp['port']).db('db')
      rescue => e
      end
      e.should_not be_nil
      EM.stop
    end
  end
end


