# frozen_string_literal: true

require_relative '../base_validator'

# 验证用例 v{NUMBER}_{MODULE}: {BRIEF_TITLE}
#
# 任务描述:
#   {DETAILED_TASK_DESCRIPTION}
#   Agent 需要完成以下操作：
#   1. {STEP_1}
#   2. {STEP_2}
#   3. {STEP_3}
#
# 复杂度分析:
#   1. {COMPLEXITY_POINT_1}
#   2. {COMPLEXITY_POINT_2}
#   3. {COMPLEXITY_POINT_3}
#
# 评分标准:
#   - {ASSERTION_1_DESCRIPTION} ({WEIGHT_1}分)
#   - {ASSERTION_2_DESCRIPTION} ({WEIGHT_2}分)
#   - {ASSERTION_3_DESCRIPTION} ({WEIGHT_3}分)
#   总分：100分
#
# 规范参考：
#   docs/conventions/validator-writing.md

class V{NUMBER_INT}{MODULE_CLASS}Validator < BaseValidator
  self.validator_id   = 'v{NUMBER}_{MODULE}_validator'
  self.task_id        = '{TASK_UUID}'  # 用 SecureRandom.uuid 生成一次，固定写进来
  self.title          = '{FULL_TASK_TITLE}'
  self.timeout_seconds = 180  # 简单 60-120 / 中等 180-240 / 复杂 300-600

  # -------------------------------------------------------------------
  # （可选）题目私有预制数据
  # - 在 prepare 之前执行，SET SESSION app.data_version 已经设置好
  # - 新建记录必须显式写 data_version: @data_version（不会污染 baseline）
  # - 只在"Agent 任务起点需要数据"时使用（例如购物车已有商品，让 Agent 继续加）
  #
  # ⚠️ seed 在 prepare 之前执行 → baseline 引用必须抽到 load_refs 里共用
  #   否则 seed 里 @user 还是 nil，belongs_to :user 校验会挂掉
  #
  # 📖 canonical 示例：app/validators/cart/v002_change_coconut_variant_validator.rb
  # -------------------------------------------------------------------
  # def seed
  #   load_refs
  #   CartItem.create!(
  #     user: @user, product: @product, quantity: 1,
  #     data_version: @data_version
  #   )
  # end

  # -------------------------------------------------------------------
  # prepare: 只查 baseline，设置实例变量，返回任务 Hash
  # - 禁止 create!（属于 simulate 阶段）
  # - 所有 baseline 查询必须带 data_version: '0'
  # - 如果有 seed 钩子，改成调 load_refs（下方）
  # -------------------------------------------------------------------
  def prepare
    # 无 seed 的简单 validator：直接查 baseline 即可
    @user    = User.find_by!(email: 'demo@rlbox.ai', data_version: '0')
    # @product = Product.find_by!(name: '{PRODUCT_NAME}', data_version: '0')
    # @category = Category.find_by!(key: '{CATEGORY_KEY}', data_version: '0')
    #
    # 有 seed 钩子的 validator 改成：
    #   load_refs
    #
    # 需要查"demo user 的默认地址"时，必须锁 baseline（RLS 会让你看到 seed 私有数据）：
    #   @home = @user.addresses.where(data_version: '0').order(created_at: :desc).first

    # 可选：预计算"最优解"，用于 verify 阶段对比
    # @expected_total = @product.price * 2

    {
      task: '{TASK_DESCRIPTION_FOR_AGENT}',
      hint: '{OPTIONAL_HINT_FOR_AGENT}'
    }
  end

  # -------------------------------------------------------------------
  # verify: 用 add_assertion 验证 Agent 操作结果
  # 规则：
  #   1. 所有查询必须带 data_version: @data_version
  #   2. where 只锁 scope，断言放在 add_assertion 块内
  #   3. 关键实体查询用 Guard clause 防 NPE
  #   4. 权重总和 = 100
  #   5. 错误消息要具体（带期望值 + 实际值）
  # -------------------------------------------------------------------
  def verify
    add_assertion '{ASSERTION_1_DESCRIPTION}', weight: {WEIGHT_1} do
      @entity = {Model}.where(user: @user, data_version: @data_version)
                       .order(created_at: :desc).first
      expect(@entity).not_to be_nil, '未找到预期的 {Model}'
    end

    # Guard clause：关键实体拿不到就不往下验
    return if @entity.nil?

    add_assertion '{ASSERTION_2_DESCRIPTION}', weight: {WEIGHT_2} do
      expect(@entity.{attribute}).to eq({expected_value}),
        "预期 #{ {expected_value}.inspect }，实际 #{ @entity.{attribute}.inspect }"
    end

    add_assertion '{ASSERTION_3_DESCRIPTION}', weight: {WEIGHT_3} do
      expect(@entity.{other}).to eq({other_expected}),
        "预期 #{ {other_expected}.inspect }，实际 #{ @entity.{other}.inspect }"
    end
  end

  # -------------------------------------------------------------------
  # simulate: 模拟 AI Agent 的正确操作，用于自动化回归
  # 规则：
  #   1. 所有 create! 必须带 data_version: @data_version（绝不 '0'）
  #   2. 可以读 baseline（data_version: '0'），也可以读本会话已写的数据
  #   3. 不要在这里手动 SET SESSION（base_validator 已做）
  # -------------------------------------------------------------------
  def simulate
    # 示例：下单流程
    # order = Order.create!(
    #   user: @user,
    #   status: 'pending',
    #   total_price: @product.price * 2,
    #   data_version: @data_version
    # )
    # order.order_items.create!(
    #   product: @product,
    #   quantity: 2,
    #   unit_price: @product.price,
    #   data_version: @data_version
    # )

    raise NotImplementedError, 'TODO: 实现 simulate（删掉本行再运行）'
  end

  private

  # -------------------------------------------------------------------
  # （可选）load_refs：当有 seed 钩子时必须抽出来
  # seed 在 prepare 之前执行 → baseline 引用不能只放 prepare 里
  # 用 `return if @user` memoize，seed 和 prepare 各调一次
  # -------------------------------------------------------------------
  # def load_refs
  #   return if @user
  #   @user    = User.find_by!(email: 'demo@rlbox.ai', data_version: '0')
  #   @product = Product.find_by!(name: '{PRODUCT_NAME}', data_version: '0')
  # end

  # -------------------------------------------------------------------
  # （可选）断言小贴士
  # - ❌ be_true / be_false —— RSpec 3 已删，会变 predicate matcher 爆 NoMethodError
  # - ✅ be_truthy / be_falsey / eq(true) / eq(false)
  # - 查"自己的" addresses / orders 时，显式 `where(data_version: '0')`
  #   否则 RLS 会把 seed 造的私有数据一起查出来
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # （可选）保存/恢复执行状态
  # 只有当 execute_prepare 和 execute_verify 是两个独立请求（真实浏览器测试），
  # 且你需要在 verify 阶段拿到 prepare 阶段的实例变量时才需要。
  # 自动化 execute_simulate 同进程，不需要。
  # -------------------------------------------------------------------
  # def execution_state_data
  #   { user_id: @user.id, product_id: @product.id }
  # end
  #
  # def restore_from_state(data)
  #   @user    = User.find_by!(id: data['user_id'], data_version: '0')
  #   @product = Product.find_by!(id: data['product_id'], data_version: '0')
  # end
end
