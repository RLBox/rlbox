# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/data_pack_loader')

RSpec.describe DataPackLoader do
  let(:tmpdir) { Dir.mktmpdir('data_pack_loader_spec') }
  after { FileUtils.rm_rf(tmpdir) }

  def write_pack(name, depends_on: nil, body: '')
    path = File.join(tmpdir, "#{name}.rb")
    lines = ['# frozen_string_literal: true']
    lines << "# depends_on: #{Array(depends_on).join(', ')}" if depends_on
    lines << body unless body.empty?
    File.write(path, lines.join("\n") + "\n")
    path
  end

  def load_order_names
    described_class.new(tmpdir).load_order.map { |p| File.basename(p, '.rb') }
  end

  describe '#load_order' do
    it 'returns [] when directory is empty' do
      expect(described_class.new(tmpdir).load_order).to eq([])
    end

    it 'falls back to alphabetic order when no depends_on declared' do
      write_pack('charlie')
      write_pack('alpha')
      write_pack('bravo')
      expect(load_order_names).to eq(%w[alpha bravo charlie])
    end

    it 'loads base.rb first implicitly when present (legacy compat)' do
      write_pack('alpha')
      write_pack('base')
      write_pack('zeta')
      expect(load_order_names).to eq(%w[base alpha zeta])
    end

    it 'respects explicit depends_on ordering' do
      write_pack('users')
      write_pack('orders', depends_on: 'users')
      write_pack('order_items', depends_on: 'orders')
      # Alphabetic would give: order_items, orders, users
      # Topological must give: users, orders, order_items
      expect(load_order_names).to eq(%w[users orders order_items])
    end

    it 'is deterministic among peers (alphabetic tiebreak)' do
      write_pack('base')
      write_pack('cart', depends_on: 'base')
      write_pack('addresses', depends_on: 'base')
      write_pack('products', depends_on: 'base')
      result = load_order_names
      expect(result.first).to eq('base')
      expect(result[1..]).to eq(%w[addresses cart products])
    end

    it 'handles multi-dep correctly' do
      write_pack('users')
      write_pack('products')
      write_pack('orders', depends_on: 'users, products')
      expect(load_order_names).to eq(%w[products users orders])
    end

    it 'raises CycleError on direct cycle' do
      write_pack('a', depends_on: 'b')
      write_pack('b', depends_on: 'a')
      expect { described_class.new(tmpdir).load_order }
        .to raise_error(DataPackLoader::CycleError, /Cycle detected/)
    end

    it 'raises CycleError on indirect cycle' do
      write_pack('a', depends_on: 'b')
      write_pack('b', depends_on: 'c')
      write_pack('c', depends_on: 'a')
      expect { described_class.new(tmpdir).load_order }
        .to raise_error(DataPackLoader::CycleError)
    end

    it 'raises MissingDependencyError when a declared dep does not exist' do
      write_pack('orphan', depends_on: 'ghost')
      expect { described_class.new(tmpdir).load_order }
        .to raise_error(DataPackLoader::MissingDependencyError, /ghost/)
    end

    it 'only scans the header region for depends_on (ignores directives later in file)' do
      # A file where a legitimate comment much later mentions "depends_on:" in
      # prose should not be parsed. We simulate by inserting real code early
      # and a bogus depends_on comment after.
      path = File.join(tmpdir, 'tricky.rb')
      File.write(path, <<~RUBY)
        # frozen_string_literal: true
        puts 'hello'
        # depends_on: does_not_exist
      RUBY
      write_pack('other')
      # Should load successfully since the depends_on line is past the header zone
      expect { described_class.new(tmpdir).load_order }.not_to raise_error
    end

    it 'treats files with depends_on: as opt-in — legacy implicit base rule still applies to siblings' do
      write_pack('base')
      write_pack('explicit', depends_on: 'base')
      write_pack('implicit') # no declaration → inherits implicit base dep
      # Both should end up after base
      order = load_order_names
      expect(order.first).to eq('base')
      expect(order).to include('explicit', 'implicit')
    end
  end
end
