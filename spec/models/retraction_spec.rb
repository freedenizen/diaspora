#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'spec_helper'

describe Retraction do

  let(:user) { make_user }
  let(:user2) { make_user }
  let(:user3) { make_user }
  let(:user4) { make_user }
  
  let(:aspect) { user.aspects.create(:name => "Bruisers") }
  let(:aspect2) { user2.aspects.create(:name => "Bruisers") }
  let(:aspect3) { user3.aspects.create(:name => "Bruisers") }
  let(:aspect4) { user4.aspects.create(:name => "Bruisers") }

  let(:person) { Factory(:person) }
  let!(:friending_users) {friend_users(user, aspect, user2, aspect2)}
  let!(:friending_users2) {friend_users(user, aspect, user3, aspect3)}
  let!(:friending_users3) {friend_users(user2, aspect2, user4, aspect4)} #this is to test sending to send sending retractions upstream
  let!(:post) { user.post :status_message, :message => "Destroy!", :to => aspect.id }



  describe 'serialization' do
    it 'should have a post id after serialization' do
      retraction = Retraction.for(post)
      xml = retraction.to_xml.to_s
      xml.include?(post.id.to_s).should == true
    end
  end

  describe 'dispatching' do
    it 'should dispatch a message on destroy' do
      pending
      Factory.create :person
      User::QUEUE.should_receive :add_post_request
      post.destroy
    end
  end
  
  describe '#for' do
    context 'comments' do
      let!(:comment) {user.comment("excellent time", :on => post) }

      it 'sets the comment_id' do
        retraction = Retraction.for(comment)
        retraction.comment_id.should == comment.id
      end
    end
  end

  describe '#perform_comment' do

    let!(:comment) {user.comment("excellent time", :on => post) }

    it 'retracts a comment with an valid signature' do
      retraction = Retraction.for(comment)
      retraction.comment_creator_signature = retraction.sign_with_key(user.encryption_key)

      lambda{ retraction.perform(user.id)}.should change(Comment, :count).by(-1)
    end

    it 'does not retract a comment with an invalid' do
      retraction = Retraction.for(comment)
      retraction.comment_creator_signature = "Invalid String"

      lambda{ retraction.perform(user.id) }.should raise_error /Comment Retraction with invalid signature/
    end
  end
   
  describe 'User#retract_coment' do
    let!(:comment) {user.comment("excellent time", :on => post) }
    let!(:comment2) {user2.comment("excellent time", :on => post) }

    it 'returns a retraction' do
      retraction = user.retract_comment(comment)
      retraction.type.should == 'Comment'
    end
    
    context 'signing' do
      it 'signs the retraction with the commentors key' do
        retraction = user.retract_comment(comment)
        retraction.comment_creator_signature.should_not be nil
        retraction.verify_signature retraction.comment_creator_signature, user.person
      end
    end

    context 'sending out' do
      it 'sends the retraction downstream' do
        user.should_receive(:push_to_person).twice
        user.retract_comment(comment)
      end

      it 'sends the retraction to the post owner' do
        user2.should_receive(:push_to_person).once
        user2.retract_comment(comment2)
      end
    end

    it 'retracts the comment on post by the author' do
      user2.reload.visible_posts.include?(post).should be true
      post.reload.comments.size.should == 2
      comment.should_not_receive(:destroy)
      user.retract_comment(comment)
      post.reload.comments.size.should == 1
    end

    it 'retracts the comment on another persons post' do
      user.visible_posts.first.comments.include?(comment2)
      comment2.reload.should_not be_nil
      retraction = user2.retract_comment(comment2)
      proc{ comment2.reload}.should raise_error /does not exist/
    end

    it 'sends a retraction downstream' do
      retraction = user2.retract_comment(comment2)
      user.should_receive(:push_to_person).once
      Retraction.should_receive(:perform).with(user.id, user3.id)
    end



  end

end
