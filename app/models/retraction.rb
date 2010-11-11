#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

class Retraction
  include ROXML
  include Diaspora::Webhooks
  include Encryptable

  xml_accessor :post_id
  xml_accessor :diaspora_handle
  xml_accessor :type
  xml_accessor :comment_id
  xml_accessor :comment_creator_signature
  

  attr_accessor :person

  def self.for(object)
    retraction = self.new
    if object.is_a? User
      retraction.post_id = object.person.id
      retraction.type = object.person.class.to_s
    elsif object.is_a? Comment
      retraction.post_id = object.post_id
      retraction.comment_id = object.id
      retraction.type = object.class.to_s
    else
      retraction.post_id = object.id
      retraction.type = object.class.to_s
    end
    retraction.diaspora_handle = object.diaspora_handle 
    retraction
  end

  def perform receiving_user_id
    Rails.logger.debug "Performing retraction for #{post_id}"

    if self.type == 'Comment'
      perform_comment receiving_user_id
      return
    else
      object = self.type.constantize.find_by_id(post_id) 
    end

    if object
      unless object.diaspora_handle == person.diaspora_handle 
        raise "#{person.inspect} is trying to retract a post they do not own"
      end

      begin
        Rails.logger.debug("Retracting #{self.type} id: #{self.post_id}")
        target = self.type.constantize.first(:id => self.post_id)
        target.unsocket_from_uid receiving_user_id if target.respond_to? :unsocket_from_uid
        target.delete
      rescue NameError
        Rails.logger.info("Retraction for unknown type recieved.")
      end
    end
  end

  def signable_string
    [self.class, self.type, self.comment_id].join ';'
  end

  private

  def perform_comment receiving_user_id
    Rails.logger.debug("Retracting #{self.type} id: #{self.comment_id}")
    comment = self.type.constantize.find_by_id(comment_id) 
    if comment
      raise "Comment Retraction with invalid signature" unless verify_signature(comment_creator_signature, comment.person)
      comment.unsocket_from_uid receiving_user_id if comment.respond_to? :unsocket_from_uid
      comment.delete
    end
  end
end
