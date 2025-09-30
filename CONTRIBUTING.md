# Contributing to scalingo-staging-sync

Thank you for your interest in contributing to scalingo-staging-sync! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before contributing.

## How Can I Contribute?

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs actual behavior
- **Environment details** (Ruby version, Rails version, PostgreSQL version)
- **Stack traces** or error messages
- **Configuration** (sanitized, without secrets)

### Suggesting Enhancements

Enhancement suggestions are welcome! Please provide:

- **Use case** - Why is this enhancement needed?
- **Proposed solution** - How should it work?
- **Alternatives considered** - What other solutions did you explore?
- **Additional context** - Screenshots, examples, etc.

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow our coding standards** (see below)
3. **Add tests** for new functionality
4. **Update documentation** as needed
5. **Ensure all tests pass** locally
6. **Submit a pull request** with a clear description

## Development Setup

### Prerequisites

- Ruby 3.4 or higher
- PostgreSQL 16.x
- Bundler

### Getting Started

```bash
# Clone your fork
git clone https://github.com/your-username/scalingo-staging-sync.git
cd scalingo-staging-sync

# Install dependencies and setup
bin/setup

# Run tests
bundle exec rake test

# Run linter
bundle exec rubocop

# Start console for testing
bin/console
```

### Running Tests

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby -Ilib:test test/path/to/test_file.rb

# Run with coverage report
COVERAGE=true bundle exec rake test
```

## Coding Standards

### Ruby Style

We use RuboCop to enforce style guidelines:

```bash
# Check style violations
bundle exec rubocop

# Auto-fix violations where possible
bundle exec rubocop -a
```

Key style points:
- Use double quotes for strings
- Frozen string literals required
- 2 spaces for indentation
- Maximum line length: 120 characters
- Maximum method length: 18 lines

### Commit Messages

Follow these guidelines for commit messages:

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit first line to 72 characters
- Reference issues and pull requests when relevant

Examples:
```
Add PostgreSQL 17 support

- Update pg gem dependency
- Add version detection logic
- Update documentation

Fixes #123
```

### Testing Guidelines

- Write tests for all new functionality
- Maintain test coverage above 90%
- Use descriptive test names
- Follow AAA pattern (Arrange, Act, Assert)
- Mock external services (Scalingo API, Slack)

Example test structure:
```ruby
class ServiceTest < Minitest::Test
  def setup
    # Arrange
    @service = Service.new
  end

  def test_performs_expected_action
    # Act
    result = @service.perform

    # Assert
    assert_equal expected_value, result
  end
end
```

## Documentation

- Update README.md for user-facing changes
- Update CLAUDE.md for implementation details
- Add inline documentation for complex methods
- Update WORKFLOW.md if the cloning process changes

## Release Process

Maintainers handle releases:

1. Update version in `lib/scalingo_staging_sync/version.rb`
2. Update CHANGELOG.md
3. Run `bundle exec rake release`
4. Create GitHub release with notes

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/navidemad/scalingo-staging-sync/discussions)
- **Bug Reports**: Open an [Issue](https://github.com/navidemad/scalingo-staging-sync/issues)
- **Security Issues**: Email navidemad@gmail.com directly

## Recognition

Contributors are recognized in:
- README.md acknowledgments
- GitHub contributors page
- Release notes for significant contributions

Thank you for helping make scalingo-staging-sync better!