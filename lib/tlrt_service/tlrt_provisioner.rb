# Copyright (c) 2009-2011 VMware, Inc.
require "tlrt_service/common"

class VCAP::Services::Tlrt::Provisioner < VCAP::Services::Base::Provisioner
  include VCAP::Services::Tlrt::Common

end

