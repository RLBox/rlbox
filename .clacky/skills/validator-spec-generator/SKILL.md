---
name: validator-spec-generator
description: 'Generate comprehensive RSpec test cases for validator files. Use this skill when the user asks to generate validator tests, test a validator, create spec for a validator file, or provides a path to a validator file ending in _validator.rb. This skill is specifically for custom validators that inherit from BaseValidator and are used for AI Agent capability testing, not Rails ActiveModel validators.'
disable-model-invocation: false
user-invocable: true
---

# Validator Spec Generator

## Purpose

Generate comprehensive RSpec test cases for custom validator files that inherit from `BaseValidator`. These validators are used for testing AI Agent capabilities, not Rails model validations.

## When to use this skill

- User explicitly asks to "generate validator tests" or "test this validator"
- User provides a path to a file ending in `_validator.rb`
- User says "create spec for [validator name]"
- User mentions testing validators in the context of AI agent testing

## Validator Structure Overview

Validators inherit from `BaseValidator` and typically have:

```ruby
class V001ExampleValidator < BaseValidator
  self.validator_id = 'v001_example_validator'
  self.task_id = 'uuid-here'
  self.title = 'Task title'
  self.description = 'Task description'

  def prepare
    # Returns a hash of parameters for the agent
    { param1: value1, param2: value2 }
  end

  def verify
    # Uses add_assertion to verify agent behavior
    add_assertion "description", weight: 20 do
      expect(something).to be_truthy
    end
  end

  def simulate
    # (Optional) Simulates AI operations for testing
    # Creates test data, etc.
  end
end
```

## File Locations

- **Validator files**: `app/validators/`
- **Spec files**: `spec/validators/`

## Workflow

### 1. Locate or accept the validator file

If the user provides a path, use it directly. Otherwise, search:

```bash
find app/validators -name "*_validator.rb" -type f
```

If multiple validators exist and user didn't specify, ask which one to test.

### 2. Read and analyze the validator

Read the validator file completely. Identify:

- **Class name** and inheritance
- **Class attributes**: `validator_id`, `task_id`, `title`, `description`
- **`prepare` method**: what parameters it returns
- **`verify` method**: all `add_assertion` blocks and their weights
- **`simulate` method**: what it creates (if present)
- **Dependencies**: any models, services, or external resources used

### 3. Generate the spec file

The spec should mirror the validator's structure and test:

#### A. Basic metadata tests

```ruby
require 'rails_helper'

RSpec.describe V001ExampleValidator do
  let(:validator) { described_class.new }

  describe 'metadata' do
    it 'has a validator_id' do
      expect(described_class.validator_id).to be_present
      expect(described_class.validator_id).to eq('v001_example_validator')
    end

    it 'has a task_id' do
      expect(described_class.task_id).to be_present
      expect(described_class.task_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'has a title' do
      expect(described_class.title).to be_present
    end

    it 'has a description' do
      expect(described_class.description).to be_present
    end
  end
end
```

#### B. Prepare method tests

Test that `prepare` returns all expected keys with correct types and values:

```ruby
describe '#prepare' do
  let(:result) { validator.prepare }

  it 'returns a hash' do
    expect(result).to be_a(Hash)
  end

  it 'includes the city parameter' do
    expect(result).to have_key(:city)
    expect(result[:city]).to eq('深圳')
  end

  it 'includes the budget parameter' do
    expect(result).to have_key(:budget)
    expect(result[:budget]).to eq(500)
  end

  it 'includes check_in_date as future date' do
    expect(result).to have_key(:check_in_date)
    expect(result[:check_in_date]).to be > Date.current
  end

  # Add test for each parameter returned by prepare
end
```

**Key principle**: For each key in the hash returned by `prepare`, create:
- A test that the key exists
- A test for the value (exact match if hardcoded, type/range check if dynamic)

#### C. Verify method tests

For each `add_assertion` block in the validator's `verify` method, create a corresponding test:

```ruby
describe '#verify' do
  context 'when assertion passes' do
    before do
      # Set up test data so assertion succeeds
      @hotel_booking = HotelBooking.create!(city: '深圳', budget: 500)
    end

    it 'passes the "订单已创建" assertion' do
      expect { validator.verify }.not_to raise_error
      # Or verify that the assertion adds no errors
    end
  end

  context 'when assertion fails' do
    before do
      # Set up test data so assertion fails
      HotelBooking.destroy_all
    end

    it 'fails the "订单已创建" assertion' do
      # Test that the assertion properly fails
      expect { validator.verify }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end
```

**Important considerations for verify tests**:
- Each assertion should be tested in both passing and failing scenarios
- If the assertion depends on database records, use `before` blocks to set up the right state
- If assertions reference instance variables (like `@hotel_booking`), those need to be set up in the test context
- Weight values should be checked if they're critical to the validator's purpose

#### D. Simulate method tests (if present)

If the validator has a `simulate` method, test its side effects:

```ruby
describe '#simulate' do
  it 'creates a hotel booking' do
    expect {
      validator.simulate
    }.to change(HotelBooking, :count).by(1)
  end

  it 'creates a booking with correct attributes' do
    validator.simulate
    booking = HotelBooking.last
    expect(booking.city).to eq('深圳')
    expect(booking.budget).to eq(500)
  end
end
```

### 4. Write the spec file to the correct location

The spec file path should mirror the validator file path:

- Validator: `app/validators/v001_example_validator.rb`
- Spec: `spec/validators/v001_example_validator_spec.rb`

Create the directory if it doesn't exist:

```bash
mkdir -p spec/validators
```

### 5. Format and style guidelines

- Use RSpec 3 syntax (`expect` not `should`)
- Use `let` and `let!` for test data setup
- Group related tests in `context` blocks
- Use descriptive test names that explain what is being tested
- Include comments for complex setup logic
- Follow the existing project's RSpec style if detectable

### 6. Handle edge cases

**Missing methods**: If `prepare`, `verify`, or `simulate` don't exist, skip those test sections.

**Complex assertions**: If an assertion uses complex RSpec matchers or custom logic, mirror that structure in the test.

**External dependencies**: If the validator calls APIs, uses background jobs, or depends on external services, add comments suggesting the use of stubs/mocks:

```ruby
# Consider stubbing external API calls:
# allow(WeatherAPI).to receive(:fetch).and_return(mock_data)
```

**Date/time dependencies**: For validators using `Date.current`, `Time.now`, etc., suggest using Timecop or similar:

```ruby
# Consider freezing time for consistent test results:
# before { travel_to Time.zone.local(2026, 4, 12, 12, 0, 0) }
```

### 7. Confirm with user and write the file

Show the user:
1. The spec file path where it will be created
2. A summary of what will be tested (number of test cases, coverage areas)
3. Any assumptions or edge cases that need manual review

Then write the file using the `write` tool.

## Example output structure

```ruby
require 'rails_helper'

RSpec.describe V001BookBudgetHotelValidator do
  let(:validator) { described_class.new }

  describe 'metadata' do
    # Tests for validator_id, task_id, title, description
  end

  describe '#prepare' do
    # Tests for each key-value pair returned
  end

  describe '#verify' do
    # Tests for each add_assertion block
    # Both passing and failing scenarios
  end

  describe '#simulate' do
    # Tests for side effects (if method exists)
  end
end
```

## Best practices

1. **Read the entire validator first** — don't start writing tests until you understand the complete structure
2. **Test behavior, not implementation** — focus on what the methods return or create, not how they do it
3. **Cover edge cases** — empty data, nil values, boundary conditions
4. **Make tests independent** — each test should be able to run in isolation
5. **Use meaningful descriptions** — someone should understand what's being tested just by reading the test name
6. **Verify weights** — if assertion weights are critical to scoring, test them explicitly

## Anti-patterns to avoid

- Don't write tests that simply repeat the validator's code
- Don't hard-code database IDs or UUIDs unless they're fixtures
- Don't skip setup/teardown — tests should be reproducible
- Don't test Rails framework behavior — focus on the validator's custom logic
- Don't write overly generic tests that pass even when the code is wrong

## When you're done

1. Write the spec file to `spec/validators/[validator_name]_spec.rb`
2. Tell the user where the file was created
3. Suggest running the tests: `rspec spec/validators/[validator_name]_spec.rb`
4. Mention any manual review needed (complex mocking, time-dependent tests, etc.)
