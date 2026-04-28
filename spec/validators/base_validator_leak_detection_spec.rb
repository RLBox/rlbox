# frozen_string_literal: true

require 'rails_helper'

# 测试 Validators::BaseValidator 的 FAIL FAST 跨请求隔离（ADR-007）
#
# 核心保证：execute_simulate 会为 verify 阶段新建一个 validator 实例，
# 只有通过 execution_state_data / restore_from_state 显式声明的状态能跨"请求"。
# 这样单进程测试就能真实复现生产环境"prepare 和 verify 是两次独立 HTTP 请求"的行为。
#
# 典型故障模式（"单机绿、浏览器红"）：
#   - prepare 里设置 @user，verify 里直接用 @user
#   - 本地 execute_simulate 旧实现同一个实例跑 → 绿
#   - 生产 verify 是新实例，@user = nil → 红
#
# 详见 docs/decisions/ADR-007-verify-cross-request-isolation.md
RSpec.describe Validators::BaseValidator, type: :validator do
  # ❌ 漏声明：prepare 设置 @foo，verify 直接用 @foo（生产环境会是 nil）
  class LeakyTestValidator < Validators::BaseValidator
    self.validator_id = 'test_leaky'
    self.task_id      = 'test-leaky-uuid'
    self.title        = 'leaky test'

    def prepare
      @foo = 'bar'
      { task: 't', hint: 'h' }
    end

    def simulate; end

    def verify
      add_assertion '使用 @foo', weight: 1 do
        expect(@foo).to eq('bar')   # verify 是新实例，@foo 是 nil，必然失败
      end
    end
  end

  # ✅ 合规姿势 A：prepare 用局部变量，verify 无需 @ivar
  class LocalVarTestValidator < Validators::BaseValidator
    self.validator_id = 'test_local'
    self.task_id      = 'test-local-uuid'
    self.title        = 'local var test'

    def prepare
      foo = 'bar'   # 局部变量，不跨请求
      { task: "t-#{foo}", hint: 'h' }
    end

    def simulate; end

    def verify
      add_assertion 'always ok', weight: 1 do
        expect(1).to eq(1)
      end
    end
  end

  # ✅ 合规姿势 D：显式声明持久化（execution_state_data + restore_from_state）
  class DeclaredTestValidator < Validators::BaseValidator
    self.validator_id = 'test_declared'
    self.task_id      = 'test-declared-uuid'
    self.title        = 'declared test'

    def prepare
      @foo = 'bar'
      { task: 't', hint: 'h' }
    end

    def execution_state_data
      super.merge(foo: @foo)
    end

    def restore_from_state(data)
      super
      @foo = data['foo']
    end

    def simulate; end

    def verify
      add_assertion '使用 @foo', weight: 1 do
        expect(@foo).to eq('bar')   # restore_from_state 恢复了 @foo
      end
    end
  end

  describe '#execute_simulate 跨请求隔离' do
    before do
      allow_any_instance_of(described_class).to receive(:ensure_baseline_data_loaded)
      allow_any_instance_of(described_class).to receive(:rollback_to_baseline)
    end

    it '漏声明的实例变量在 verify 阶段变 nil，assertion 失败' do
      v = LeakyTestValidator.new
      result = v.execute_simulate
      expect(result[:status]).to eq('failed')
      # @foo 是 nil，eq('bar') 断言会失败
      expect(result[:verify_result][:assertions].first[:passed]).to be false
    end

    it '局部变量模式正常通过' do
      v = LocalVarTestValidator.new
      result = v.execute_simulate
      expect(result[:status]).to eq('passed'), "预期 passed，实际: #{result.inspect}"
    end

    it '显式声明持久化的实例变量在 verify 阶段正常恢复' do
      v = DeclaredTestValidator.new
      result = v.execute_simulate
      expect(result[:status]).to eq('passed'), "预期 passed，实际: #{result.inspect}"
    end
  end
end
