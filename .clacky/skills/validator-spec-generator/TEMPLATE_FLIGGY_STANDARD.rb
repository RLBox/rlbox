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
#   ❌ 不能一次性提供：需要先{STEP_A}→{STEP_B}→{STEP_C}
# 
# 评分标准:
#   - {ASSERTION_1_DESCRIPTION} ({WEIGHT_1}分)
#   - {ASSERTION_2_DESCRIPTION} ({WEIGHT_2}分)
#   - {ASSERTION_3_DESCRIPTION} ({WEIGHT_3}分)
#   - {ASSERTION_N_DESCRIPTION} ({WEIGHT_N}分)
#   总分：100分
# 
# 使用方法:
#   # 准备阶段
#   POST /api/tasks/v{NUMBER}_{MODULE}_validator/start
#   
#   # Agent 通过界面操作完成任务...
#   
#   # 验证结果
#   POST /api/verify/:execution_id/result

class V{NUMBER_INT}{MODULE_CLASS}Validator < BaseValidator
  self.validator_id = 'v{NUMBER}_{MODULE}_validator'
  self.task_id = '{TASK_UUID}'  # TODO: 生成或使用固定 UUID
  self.title = '{FULL_TASK_TITLE}'
  self.timeout_seconds = 300  # TODO: 根据任务复杂度调整（简单任务 60-120s，复杂任务 300-600s）

  # 准备阶段：设置任务参数并返回给 Agent
  def prepare
    # TODO: 设置业务参数（实例变量）
    # 示例：
    # @city = '深圳'
    # @budget = 500
    # @check_in_date = Date.current + 2.days  # 相对日期："后天"
    # @nights = 1
    # @check_out_date = @check_in_date + @nights.days
    
    # TODO: 查询基线数据（data_version=0），找到"正确答案"
    # 用途：为 verify 方法提供验证依据
    # 示例：
    # eligible_items = {ModelName}.where(
    #   {core_field}: @{param},
    #   data_version: 0
    # ).where('EXISTS (...子查询...)')  # 可选：复杂筛选条件
    
    # TODO: 计算最优解（如果需要验证"最优选择"）
    # 示例：
    # @best_item = eligible_items.max_by { |item| item.rating / item.price.to_f }
    
    # TODO: 返回任务信息（必需）
    # 必需字段：task
    # 可选字段：根据业务需求添加，帮助 Agent 理解任务
    {
      task: "{TASK_DESCRIPTION_FOR_AGENT}",  # 必需：简短的任务描述
      # TODO: 添加核心参数
      # {param_name}: @{param_name},
      # date_description: "入住：后天（#{@check_in_date.strftime('%Y年%m月%d日')}）",
      # hint: "系统中有多家酒店可选，请选择性价比最高的",
      # available_items_count: eligible_items.count
    }
  end

  # 验证阶段：检查 Agent 的操作结果是否符合要求
  def verify
    # ==========================================
    # 🔴 断言1（权重最高）：查询核心实体并存储
    # ==========================================
    # 说明：
    # - 必须首先执行，为后续断言准备数据
    # - 只过滤核心实体（如城市、路线），不过滤待验证属性（如日期、价格）
    # - 使用 data_version: @data_version 隔离测试数据
    # - 存储到实例变量（如 @booking），供后续断言使用
    
    add_assertion "{ENTITY_NAME}已创建", weight: 20 do  # TODO: 调整权重（20-25 分）
      # TODO: 根据业务模型修改查询
      # 示例：查询酒店订单
      # all_bookings = HotelBooking
      #   .joins(:hotel)  # 关联查询
      #   .includes(:hotel, :hotel_room)  # 预加载避免 N+1
      #   .where(hotels: { city: @city })  # ✅ 只过滤核心实体
      #   .where(data_version: @data_version)  # ✅ 会话隔离
      #   .order(created_at: :desc)  # ✅ 取最新
      #   .to_a
      
      # TODO: 修改实体名称
      all_items = {ModelName}
        .where({core_field}: @{core_param})  # ✅ 核心实体过滤
        .where(data_version: @data_version)  # ✅ 必需
        .order(created_at: :desc)
        .to_a
      
      expect(all_items).not_to be_empty, 
        "未找到任何{ENTITY_DESCRIPTION}记录"  # TODO: 自定义错误消息
      
      @item = all_items.first  # TODO: 修改实例变量名
    end
    
    # ==========================================
    # 🛡️ Guard Clause：防御式编程
    # ==========================================
    # 说明：如果核心实体不存在，后续断言无法继续
    return unless @item  # TODO: 修改实例变量名
    
    # ==========================================
    # 🟢 断言2-N：验证具体属性
    # ==========================================
    
    # TODO: 添加核心属性验证（权重 10-15 分）
    add_assertion "{CORE_ATTRIBUTE}正确（{EXPECTED_VALUE}）", weight: 15 do
      expect(@item.{attribute}).to eq(@{expected}),
        "{ATTRIBUTE_NAME}错误。期望: #{@{expected}}, 实际: #{@item.{attribute}}"
    end
    
    # TODO: 添加日期/时间验证（权重 10-15 分）
    add_assertion "{DATE_ATTRIBUTE}正确（{DATE_DESCRIPTION}）", weight: 15 do
      expect(@item.{date_field}).to eq(@{target_date}),
        "{DATE_NAME}错误。期望: #{@{target_date}}（{DATE_HINT}），实际: #{@item.{date_field}}"
    end
    
    # TODO: 添加价格/预算验证（权重 15-20 分）
    add_assertion "价格符合预算（{BUDGET_DESCRIPTION}）", weight: 20 do
      actual_price = @item.{price_field}  # TODO: 修改价格字段
      expect(actual_price <= @budget).to be_truthy,
        "价格超出预算。期望: ≤#{@budget}元, 实际: #{actual_price}元"
    end
    
    # TODO: 添加人数/数量验证（权重 5-10 分）
    add_assertion "{COUNT_ATTRIBUTE}正确（{EXPECTED_COUNT}）", weight: 5 do
      expect(@item.{count_field}).to eq(@{expected_count}),
        "{COUNT_NAME}错误。期望: #{@{expected_count}}, 实际: #{@item.{count_field}}"
    end
    
    # TODO: 添加联系人信息验证（权重 5-10 分）
    add_assertion "{CONTACT_INFO}正确（{EXPECTED_CONTACT}）", weight: 10 do
      expect(@item.{contact_name_field}).to eq('{EXPECTED_NAME}'),
        "{CONTACT_FIELD}错误。期望: {EXPECTED_NAME}（demo_user 数据）, 实际: #{@item.{contact_name_field}}"
      expect(@item.{contact_phone_field}).to eq('{EXPECTED_PHONE}'),
        "联系电话错误。期望: {EXPECTED_PHONE}, 实际: #{@item.{contact_phone_field}}"
    end
    
    # ==========================================
    # 🔵 高级断言：验证"最优选择"（权重 10-30 分）
    # ==========================================
    # 说明：验证 Agent 是否选择了"最早"、"最便宜"、"性价比最高"等最优项
    
    # TODO: 如果任务要求选择"最优项"，添加此断言
    add_assertion "选择了{OPTIMIZATION_GOAL}", weight: 10 do  # TODO: 调整权重（10-30 分）
      # 重新查询所有符合条件的候选项
      eligible_items = {ModelName}.where(
        {core_field}: @{core_param},
        data_version: 0
      )  # TODO: 添加必要的筛选条件
      
      # 计算最优项
      # 示例：性价比最高 = 评分 / 价格
      # best_item = eligible_items.max_by { |item| item.rating / item.price.to_f }
      # 示例：最早时间
      # best_item = eligible_items.min_by { |item| item.departure_time }
      # 示例：最便宜
      # best_item = eligible_items.min_by { |item| item.price }
      
      best_item = eligible_items.{OPTIMIZATION_METHOD}  # TODO: 选择优化方法
      
      expect(@item.id).to eq(best_item.id),
        "未选择{OPTIMIZATION_GOAL}。" \
        "应选: #{best_item.{display_field}}({METRICS})，" \
        "实际选择: #{@item.{display_field}}({METRICS})"
    end
  end

  # 模拟 AI Agent 操作：自动创建符合要求的数据（用于回归测试）
  def simulate
    # TODO: 实现自动化逻辑
    
    # ==========================================
    # 1️⃣ 查找测试用户（基线数据）
    # ==========================================
    user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
    
    # ==========================================
    # 2️⃣ 获取联系人信息（如果需要）
    # ==========================================
    # TODO: 如果任务需要联系人信息，取消注释
    # contact = user.contacts.find_by!(name: '张三', data_version: 0)
    
    # ==========================================
    # 3️⃣ 执行复杂查询：找到"正确答案"
    # ==========================================
    # TODO: 复用 prepare 方法的查询逻辑
    # 示例：查找符合预算的酒店，选择性价比最高的
    # eligible_items = {ModelName}.where(
    #   {core_field}: @{param},
    #   data_version: 0
    # ).where('EXISTS (...)')
    # 
    # target_item = eligible_items.max_by { |item| item.rating / item.price.to_f }
    
    # ==========================================
    # 4️⃣ 查找关联资源（如房型、座位）
    # ==========================================
    # TODO: 如果需要查找关联资源，取消注释
    # related_item = {RelatedModel}.where(
    #   {foreign_key}: target_item.id,
    #   {category_field}: '{CATEGORY_VALUE}'
    # ).order({price_field}).first
    
    # ==========================================
    # 5️⃣ 创建订单记录（完整字段）
    # ==========================================
    # TODO: 根据业务模型修改
    # 示例：创建酒店订单
    # item = {ModelName}.create!(
    #   {field_1}: {value_1},
    #   {field_2}: {value_2},
    #   user_id: user.id,
    #   data_version: @data_version  # ✅ 会话隔离
    # )
    
    # ==========================================
    # 6️⃣ 返回操作信息（Hash）
    # ==========================================
    # TODO: 返回关键操作信息
    {
      action: 'create_{entity_name}',
      {entity_name}_id: nil,  # TODO: 填充实际 ID
      message: '这是占位代码，请根据实际业务逻辑实现 simulate 方法'
    }
  end

  private

  # 保存执行状态数据（序列化到数据库）
  def execution_state_data
    # TODO: 保存关键实例变量
    # 说明：
    # - 只保存简单类型（字符串、数字、布尔值）
    # - 日期使用 to_s 保存
    # - 对象只保存 ID
    {
      # TODO: 根据实际业务参数修改
      # {param_name}: @{param_name},
      # {date_param}: @{date_param}.to_s,
      # {object_param}_id: @{object_param}&.id
    }
  end

  # 从状态恢复实例变量（从数据库反序列化）
  def restore_from_state(data)
    # TODO: 恢复实例变量
    # 说明：
    # - 日期使用 Date.parse 恢复
    # - 对象使用 find_by 重新查询
    
    # TODO: 根据实际业务参数修改
    # @{param_name} = data['{param_name}']
    # @{date_param} = Date.parse(data['{date_param}'])
    # @{object_param} = {ModelName}.find_by(id: data['{object_param}_id']) if data['{object_param}_id']
  end
end
