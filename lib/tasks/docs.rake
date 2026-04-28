# frozen_string_literal: true

# Documentation health checks (inspired by Karpathy's LLM Wiki "lint" operation).
#
# Run:
#   bin/rake docs:lint        # 全部检查
#   bin/rake docs:stats       # 页面统计
#   bin/rake docs:orphans     # 找孤儿页（无反向链接）
#   bin/rake docs:stale       # 找 >30 天未更新的页
#
# These tasks are read-only; they never modify files.

require 'yaml'
require 'set'

namespace :docs do
  DOCS_ROOT = Rails.root.join('docs').to_s

  # ---------- helpers ----------

  def all_doc_files
    Dir.glob(File.join(DOCS_ROOT, '**/*.md'))
  end

  def read_frontmatter(path)
    content = File.read(path)
    return {} unless content.start_with?('---')

    _, yaml_block, _rest = content.split(/^---\s*$/, 3)
    return {} if yaml_block.nil?

    YAML.safe_load(yaml_block, permitted_classes: [Date, Time]) || {}
  rescue StandardError
    {}
  end

  def extract_md_links(content)
    # Match [text](path.md) and [text](path.md#anchor)
    content.scan(/\]\(([^)]+\.md)(?:#[^)]*)?\)/).flatten
  end

  def relative_to_docs(abs_path)
    abs_path.sub(DOCS_ROOT + '/', '')
  end

  # ---------- tasks ----------

  desc 'Run all documentation health checks'
  task lint: :environment do
    puts "\n🔍 docs:lint — #{DOCS_ROOT}\n"

    problems = []
    problems += check_missing_frontmatter
    problems += check_broken_links
    problems += check_stale_model_whitelist
    problems += check_archive_referenced_in_wiki
    problems += check_code_antipatterns

    if problems.empty?
      puts "\n✅ All checks passed"
    else
      puts "\n❌ #{problems.size} issue(s) found:"
      problems.each { |p| puts "  - #{p}" }
      exit 1
    end
  end

  # --- 1. frontmatter ---
  def check_missing_frontmatter
    # 只检查新 wiki 目录（architecture/ conventions/ decisions/ models/）
    # 豁免：archive/（历史原文，保持原样）
    scope = %w[architecture conventions decisions models].flat_map do |sub|
      Dir.glob(File.join(DOCS_ROOT, sub, '**/*.md'))
    end
    scope += [File.join(DOCS_ROOT, 'INDEX.md')]
    bad = scope.reject { |f| read_frontmatter(f).key?('topic') }
    bad.map { |f| "missing frontmatter `topic`: #{relative_to_docs(f)}" }
  end

  # --- 2. broken links ---
  def check_broken_links
    scope = %w[architecture conventions decisions models].flat_map do |sub|
      Dir.glob(File.join(DOCS_ROOT, sub, '**/*.md'))
    end
    scope += [File.join(DOCS_ROOT, 'INDEX.md')]

    errors = []
    scope.each do |src|
      content = File.read(src)
      dir = File.dirname(src)
      extract_md_links(content).each do |link|
        next if link.start_with?('http')
        target = File.expand_path(link, dir)
        unless File.exist?(target)
          errors << "broken link in #{relative_to_docs(src)}: -> #{link}"
        end
      end
    end
    errors
  end

  # --- 3. 历史旅行项目残留检测 ---
  # 这些是 rlbox 从旅行项目演化过来时遗留的旧模型名。
  # 在 wiki 的 architecture/ conventions/ decisions/ models/ 里出现这些词 → 可能是过时内容。
  # 豁免：在 frontmatter 里写 `allow_legacy_models_for_contrast: true`（对比/反面教材用途）。
  LEGACY_TRAVEL_MODELS = %w[
    CarOrder HotelBooking TrainBooking TourGroupBooking TicketOrder
    ActivityOrder BusTicketOrder CharterBooking DeepTravelBooking
    CruiseOrder HotelPackageOrder InsuranceOrder VisaOrder
    InternetOrder AbroadTicketOrder MembershipOrder Flight Train Hotel
    Car Ticket Attraction TourGroupProduct
  ].freeze

  def check_stale_model_whitelist
    errors = []
    scope = %w[architecture conventions decisions models].flat_map do |sub|
      Dir.glob(File.join(DOCS_ROOT, sub, '**/*.md'))
    end
    scope.each do |f|
      content = File.read(f)
      next if read_frontmatter(f)['allow_legacy_models_for_contrast']

      hits = LEGACY_TRAVEL_MODELS.select { |m| content =~ /\b#{m}\b/ }
      unless hits.empty?
        errors << "legacy travel model in #{relative_to_docs(f)}: #{hits.join(', ')} — add `allow_legacy_models_for_contrast: true` to frontmatter if intentional"
      end
    end
    errors
  end

  # --- 4. archive 里的东西不应该被 wiki 主页直接引用 ---
  def check_archive_referenced_in_wiki
    errors = []
    %w[architecture conventions decisions models].each do |sub|
      Dir.glob(File.join(DOCS_ROOT, sub, '**/*.md')).each do |f|
        content = File.read(f)
        if content.scan(/\]\(([^)]*archive\/[^)]+)\)/).any?
          # 允许在 "References / 历史参考" 段落下引用 archive
          next if content =~ /历史参考|历史修复|References/
          errors << "wiki page links to archive without 'References' context: #{relative_to_docs(f)}"
        end
      end
    end
    errors
  end

  # --- 5. 反面代码模式检测（扫 app/ 代码，防止 Agent 复现已知错误）---
  #
  # 系统表白名单：ADR-003 规定只有这些表允许用三件套。
  # 派生项目 fork 后，这个白名单通常不需要改动（系统表很少变化）。
  SYSTEM_TABLE_MODELS = %w[
    Administrator Session AdminOplog ValidatorExecution
    ActiveStorage::Blob ActiveStorage::Attachment ActiveStorage::VariantRecord
  ].freeze

  def check_code_antipatterns
    errors = []

    # A. 业务 model 用 data_version_excluded! / unscope default_scope（违反 ADR-001/003）
    model_glob = Rails.root.join('app/models/**/*.rb').to_s
    Dir.glob(model_glob).each do |f|
      content = File.read(f)
      next if f.include?('/concerns/') || f.end_with?('application_record.rb')

      class_name = File.basename(f, '.rb').camelize
      next if SYSTEM_TABLE_MODELS.include?(class_name)

      if content =~ /^\s*data_version_excluded!/
        errors << "business model uses data_version_excluded! (only allowed for system tables, see ADR-003): #{f.sub("#{Rails.root}/", '')}"
      end
      if content =~ /unscope\(where:\s*:data_version\)/
        errors << "business model unscopes data_version (violates ADR-001): #{f.sub("#{Rails.root}/", '')}"
      end
    end

    # B. validator 的 simulate/seed 方法里创建 data_version: '0' 记录（污染 baseline）
    validator_glob = Rails.root.join('app/validators/**/*.rb').to_s
    Dir.glob(validator_glob).each do |f|
      next if f.include?('/support/data_packs/') # data_pack 就是要写 '0'
      content = File.read(f)

      # 检查 simulate 方法体
      if content =~ /def simulate\b(.*?)(?=^\s+def |\nend\s*\n)/m
        body = Regexp.last_match(1)
        if body =~ /data_version:\s*['"]0['"]/
          errors << "simulate method creates data_version='0' record (pollutes baseline): #{f.sub("#{Rails.root}/", '')}"
        end
      end

      # 检查 seed 方法体
      if content =~ /def seed\b(.*?)(?=^\s+def |\nend\s*\n)/m
        body = Regexp.last_match(1)
        if body =~ /data_version:\s*['"]0['"]/
          errors << "seed method creates data_version='0' record (pollutes baseline): #{f.sub("#{Rails.root}/", '')}"
        end
      end
    end

    # C. data_packs 文件里用 find_or_create_by!（应该用 insert_all）
    data_pack_glob = Rails.root.join('app/validators/support/data_packs/**/*.rb').to_s
    Dir.glob(data_pack_glob).each do |f|
      content = File.read(f)
      if content =~ /\bfind_or_create_by!?\b/
        errors << "data pack uses find_or_create_by (use insert_all per data-packs.md): #{f.sub("#{Rails.root}/", '')}"
      end
    end

    errors
  end

  desc 'Show doc statistics'
  task stats: :environment do
    files = all_doc_files
    with_fm = files.count { |f| read_frontmatter(f).key?('topic') }
    stubs = files.count { |f| read_frontmatter(f)['status'] == 'stub' }
    puts "📊 Doc stats"
    puts "   Total pages:    #{files.size}"
    puts "   With topic:     #{with_fm}"
    puts "   Stubs:          #{stubs}"
    puts "   Archived:       #{Dir.glob(File.join(DOCS_ROOT, 'archive/**/*.md')).size}"
    puts "   ADRs:           #{Dir.glob(File.join(DOCS_ROOT, 'decisions/ADR-*.md')).size}"
  end

  desc 'Find orphan pages (no inbound links)'
  task orphans: :environment do
    inbound = Hash.new(0)
    all_doc_files.each do |src|
      content = File.read(src)
      dir = File.dirname(src)
      extract_md_links(content).each do |link|
        target = File.expand_path(link, dir)
        inbound[target] += 1 if target.start_with?(DOCS_ROOT)
      end
    end

    orphans = all_doc_files.reject do |f|
      %w[INDEX.md README.md].include?(File.basename(f)) ||
        relative_to_docs(f).start_with?('archive/') ||
        inbound[f].positive?
    end

    if orphans.empty?
      puts '✅ No orphan pages'
    else
      puts "⚠️  #{orphans.size} orphan page(s):"
      orphans.each { |o| puts "   - #{relative_to_docs(o)}" }
    end
  end

  desc 'Find pages not updated in 30+ days'
  task stale: :environment do
    threshold = 30
    cutoff = Date.today - threshold
    stale = []
    all_doc_files.each do |f|
      fm = read_frontmatter(f)
      updated = fm['updated_at']
      updated = Date.parse(updated.to_s) rescue nil
      if updated.nil? || updated < cutoff
        stale << [relative_to_docs(f), updated || '(missing)']
      end
    end

    if stale.empty?
      puts "✅ All pages updated within #{threshold} days"
    else
      puts "⏰ #{stale.size} stale page(s) (>#{threshold} days):"
      stale.each { |f, d| puts "   - #{f} (#{d})" }
    end
  end
end
