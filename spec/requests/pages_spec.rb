require 'rails_helper'

RSpec.describe "Pages", type: :request do

  # Uncomment this if controller need authentication
  # let(:user) { last_or_create(:user) }
  # before { sign_in_as(user) }

  describe "GET /features" do
    it "returns http success" do
      get features_path
      expect(response).to be_success_with_view_check('features')
    end
  end


  describe "GET /about" do
    it "returns http success" do
      get about_path
      expect(response).to be_success_with_view_check('about')
    end
  end

end
