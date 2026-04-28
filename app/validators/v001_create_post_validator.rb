# frozen_string_literal: true

require_relative 'base_validator'

# 验证用例 v001_create_post: 创建帖子
# 
# 任务描述:
#   Agent 需要在系统中创建一个标题为 "Hello World"、状态为 "published" 的帖子。
# 
# 复杂度分析:
#   1. 需要导航到帖子创建页面
#   2. 填写帖子标题和状态
#   3. 确保数据正确保存到数据库
# 
# 评分标准:
#   - 帖子创建成功 (60分)
#   - 帖子状态正确 (40分)
# 
# 使用方法:
#   # 准备阶段
#   POST /api/tasks/v001_create_post/start
#   
#   # Agent 完成任务...
#   
#   # 验证结果
#   POST /api/verify/:execution_id/result

class Validators::V001CreatePostValidator < Validators::BaseValidator
  self.validator_id = 'v001_create_post'
  self.task_id = SecureRandom.uuid
  self.title = '创建帖子'
  self.timeout_seconds = 60

  def prepare
    # Baseline data (e.g. users) is already loaded by the initializer.
    # Nothing extra to set up for this simple validator.
    @expected_title = 'Hello World'
    @expected_status = 'published'
    
    {
      task: "请创建一个标题为 '#{@expected_title}'、状态为 '#{@expected_status}' 的帖子",
      hint: '导航到帖子管理页面并创建新帖子'
    }
  end

  def verify
    @post = Post.find_by(title: @expected_title, data_version: @data_version)
    
    # 断言1: 检查帖子是否创建成功
    add_assertion "帖子创建成功", weight: 60 do
      expect(@post).not_to be_nil,
        "未找到标题为 '#{@expected_title}' 的帖子"
    end
    
    # 断言2: 检查帖子状态
    add_assertion "帖子状态正确", weight: 40 do
      expect(@post&.status).to eq(@expected_status),
        "帖子状态不符合预期。期望: #{@expected_status}, 实际: #{@post&.status || '(无)'}"
    end
  end

  # 用于自动化回归测试
  def simulate
    # Step 1: 查找基线用户
    user = User.where(data_version: 0).first
    raise 'No users in baseline data' unless user

    # Step 2: 创建帖子
    @post = Post.create!(
      title: @expected_title,
      status: @expected_status,
      body: 'Created by V001CreatePostValidator simulate.',
      user: user,
      data_version: @data_version
    )

    # Step 3: 返回结果
    {
      action: 'create_post',
      result: 'success',
      message: "已创建帖子 '#{@expected_title}'，状态为 '#{@expected_status}'"
    }
  end

  private

  # 保存执行状态数据
  def execution_state_data
    {
      expected_title: @expected_title,
      expected_status: @expected_status
    }
  end

  # 从状态恢复实例变量
  def restore_from_state(data)
    @expected_title = data['expected_title']
    @expected_status = data['expected_status']
  end
end
