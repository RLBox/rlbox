# frozen_string_literal: true

# FrozenTime Initializer
#
# ── 解决的问题 ────────────────────────────────────────────────────────────────
#   基线数据包以 Date.current 为锚点生成未来 N 天的数据。
#   部署超过 N 天后，验证器 prepare 里的 Date.current + N.days 超出数据范围，
#   导致验证失败（如"数据包缺少 X 路线的班次"）。
#
# ── 解决方案 ──────────────────────────────────────────────────────────────────
#   Monkey-patch Time.now / Date.today / DateTime.now / Time.current，
#   将应用感知到的"当前时间"冻结到基线数据生成时刻。
#   无论实际经过多少天，验证器始终认为"今天"是数据包生成的那天。
#
# ── 默认行为（按环境）─────────────────────────────────────────────────────────
#   production   → 默认启用（部署后保证验证器数据始终有效）
#   development  → 默认关闭（本地开发通常需要真实时间）
#   test         → 始终关闭（测试框架有自己的时间控制）
#
# ── 手动覆盖 ──────────────────────────────────────────────────────────────────
#   在 .env（或环境变量）中设置：
#     FREEZE_TIME=true   强制启用（在 development 中开启冻结）
#     FREEZE_TIME=false  强制关闭（在 production 中关闭冻结，慎用）
#
# ── 锚点选取 ──────────────────────────────────────────────────────────────────
#   取数据库中 data_version=0 的第一条基线记录的 created_at。
#   具体模型由子应用配置 FREEZE_TIME_ANCHOR_MODEL（默认 City）。
#   如该模型不存在或没有基线数据，则跳过冻结并记录日志。

Rails.application.config.after_initialize do
  # ── 1. 测试环境始终跳过 ──────────────────────────────────────────────────────
  next if Rails.env.test?

  # ── 2. 计算是否启用 ──────────────────────────────────────────────────────────
  #   FREEZE_TIME 环境变量可显式覆盖；未设置时按环境默认值决定。
  #   支持从 .env 文件中读取（dotenv-rails 或 Rails 7.1+ credentials 均可）。
  freeze_time_enabled =
    case ENV['FREEZE_TIME']
    when 'true'  then true
    when 'false' then false
    else
      # 未显式设置：production 默认开启，其他环境默认关闭
      Rails.env.production?
    end

  next unless freeze_time_enabled

  begin
    # ── 3. 找到锚点模型 ─────────────────────────────────────────────────────────
    #   支持通过 FREEZE_TIME_ANCHOR_MODEL 环境变量自定义（默认 "City"）
    anchor_model_name = ENV.fetch('FREEZE_TIME_ANCHOR_MODEL', 'City')
    anchor_model = anchor_model_name.constantize

    # 确保表存在（避免在 db:migrate 过程中出错）
    next unless ActiveRecord::Base.connection.table_exists?(anchor_model.table_name)

    # ── 4. 查找基线数据的时间锚点 ──────────────────────────────────────────────
    anchor_record = anchor_model.where(data_version: 0).order(:created_at).first

    unless anchor_record
      # 基线数据尚未加载（首次部署 / 数据库重置期间），跳过冻结
      # validator_baseline.rb 会在同一次 after_initialize 中加载基线数据，
      # 下次重启时 frozen_time.rb 将正常冻结。
      Rails.logger.info '[FrozenTime] 基线数据尚未存在，跳过时间冻结（将在下次重启时生效）'
      next
    end

    anchor_time = anchor_record.created_at
    frozen_date = anchor_time.to_date

    # ── 5. 输出启动日志 ─────────────────────────────────────────────────────────
    puts ''
    puts '=' * 70
    puts "🕐 FrozenTime: 时间已冻结到基线数据生成日 [#{Rails.env}]"
    puts "   基线数据生成时间: #{anchor_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "   冻结日期:         #{frozen_date.strftime('%Y-%m-%d (%A)')}"
    puts "   锚点模型:         #{anchor_model_name} (data_version=0)"
    puts '   Time.now / Date.today / Time.current 均已冻结。'
    puts '   如需关闭，在 .env 中设置 FREEZE_TIME=false'
    puts '=' * 70
    puts ''

    # ── 6. Monkey-patch ─────────────────────────────────────────────────────────

    # 保存到常量，patch 方法内部引用（避免闭包变量被 GC）
    ::FrozenAnchorTime = anchor_time.freeze unless defined?(::FrozenAnchorTime)

    # 6a. Time.now → 始终返回冻结时刻
    Time.class_eval do
      class << self
        alias_method :original_now_before_freeze, :now unless method_defined?(:original_now_before_freeze)

        def now
          ::FrozenAnchorTime
        end
      end
    end

    # 6b. Date.today → 与 patched Time.now 一致
    Date.class_eval do
      class << self
        alias_method :original_today_before_freeze, :today unless method_defined?(:original_today_before_freeze)

        def today
          ::Time.now.to_date
        end
      end
    end

    # 6c. DateTime.now → 与 patched Time.now 一致
    DateTime.class_eval do
      class << self
        alias_method :original_now_before_freeze, :now unless method_defined?(:original_now_before_freeze)

        def now
          ::Time.now.to_datetime
        end
      end
    end

    # 6d. ActiveSupport::TimeZone#now → 使 Time.current / Date.current 正确工作
    #     Rails 的 Time.current 最终调用 Time.zone.now（TimeZone 实例方法）
    ActiveSupport::TimeZone.class_eval do
      unless method_defined?(:original_now_before_freeze)
        alias_method :original_now_before_freeze, :now
      end

      def now
        ::Time.now.in_time_zone(self)
      end
    end

    Rails.logger.info "[FrozenTime] 时间已冻结到 #{frozen_date}"

  rescue NameError => e
    Rails.logger.warn "[FrozenTime] 锚点模型不存在（#{e.message}），跳过时间冻结"
  rescue StandardError => e
    # 冻结失败不应影响应用启动
    Rails.logger.error "[FrozenTime] 初始化失败: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end
