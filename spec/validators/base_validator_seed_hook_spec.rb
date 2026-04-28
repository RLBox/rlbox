# frozen_string_literal: true

require 'rails_helper'

# 测试 Validators::BaseValidator 的 seed 生命周期钩子
# 约定：
#   1. 子类定义 seed 方法时，会在 prepare 之前自动调用
#   2. seed 中创建的记录会带 @data_version（会话私有，不污染 baseline）
#   3. 未定义 seed 的 validator 不受影响（向后兼容）
#
# 详见 docs/decisions/ADR-005-validator-seed-hook.md
RSpec.describe 'Validators::BaseValidator seed hook' do
  # 确保 baseline demo 用户存在
  before do
    ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")
    User.find_or_create_by!(email: 'demo@example.com') do |u|
      u.name       = 'demo'
      u.password   = 'password'
      u.data_version = '0'
    end
  end

  after do
    ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")
    # 清理本次 spec 产生的 validator_executions（测试专用 validator_id 前缀）
    ValidatorExecution.where("validator_id LIKE 'test_%'").delete_all
  end

  describe '执行顺序' do
    let(:validator_class) do
      Class.new(Validators::BaseValidator) do
        self.validator_id   = 'test_seed_order'
        self.title          = 'seed 顺序测试'
        self.timeout_seconds = 60

        attr_reader :call_order

        def seed
          @call_order = [:seed]
        end

        def prepare
          @call_order << :prepare
          { task: 'order test' }
        end

        def verify; end
        def simulate; end
      end
    end

    it 'seed 在 prepare 之前被调用' do
      validator = validator_class.new
      validator.execute_prepare
      expect(validator.call_order).to eq([:seed, :prepare])
    end
  end

  describe '数据隔离' do
    let(:validator_class) do
      Class.new(Validators::BaseValidator) do
        self.validator_id   = 'test_seed_isolation'
        self.title          = 'seed 隔离测试'
        self.timeout_seconds = 60

        attr_reader :seeded_post

        def seed
          user = User.find_by!(email: 'demo@example.com', data_version: '0')
          @seeded_post = Post.create!(
            title: 'Seed isolation test post',
            status: 'draft',
            user: user,
            body: 'seed test'
          )
        end

        def prepare
          { task: 'isolation test' }
        end

        def verify; end
        def simulate; end
      end
    end

    it 'seed 创建的记录 data_version = @data_version（不是 0）' do
      validator = validator_class.new
      validator.execute_prepare

      post = validator.seeded_post
      expect(post).not_to be_nil
      expect(post.data_version).not_to eq('0')
      expect(post.data_version).to match(/\A[a-f0-9]{16}\z/) # SecureRandom.hex(8) = 16 chars
    end

    it 'seed 数据不会污染 baseline（切回 data_version=0 查不到）' do
      validator = validator_class.new
      validator.execute_prepare
      seeded_id = validator.seeded_post.id

      # 切回 baseline 视角
      ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")
      leaked = Post.where(id: seeded_id, data_version: '0').first
      expect(leaked).to be_nil
    end
  end

  describe '向后兼容' do
    let(:validator_class) do
      Class.new(Validators::BaseValidator) do
        self.validator_id   = 'test_no_seed'
        self.title          = '无 seed 兼容测试'
        self.timeout_seconds = 60

        def prepare
          { task: 'no seed' }
        end

        def verify; end
        def simulate; end
      end
    end

    it '未定义 seed 的 validator 正常执行 prepare' do
      validator = validator_class.new
      expect { validator.execute_prepare }.not_to raise_error
    end
  end
end
