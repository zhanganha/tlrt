# Copyright (c) 2009-2011 VMware, Inc.

class VCAP::Services::Tlrt::TlrtError < VCAP::Services::Base::Error::ServiceError
    TLRT_DISK_FULL = [31201, HTTP_INTERNAL, 'Node disk is full.']
    TLRT_CONFIG_NOT_FOUND = [31202, HTTP_NOT_FOUND, 'Tlrt configuration %s not found.']
    TLRT_CRED_NOT_FOUND = [31203, HTTP_NOT_FOUND, 'Tlrt credential %s not found.']
    TLRT_LOCAL_DB_ERROR = [31204, HTTP_INTERNAL, 'Tlrt node local db error.']
    TLRT_INVALID_PLAN = [31205, HTTP_INTERNAL, 'Invalid plan %s.']
    TLRT_BAD_SERIALIZED_DATA = [31207, HTTP_BAD_REQUEST, "File %s can't be verified"]
end
