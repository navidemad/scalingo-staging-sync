# frozen_string_literal: true

require "test_helper"

class ScalingoApiClientTest < Minitest::Test
  def setup
    super
    stub_rails
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
    @app_name = "test-app"

    with_env("SCALINGO_API_TOKEN" => "test_token_123")
  end

  def teardown
    unstub_rails
    super
  end

  describe "initialization" do
    def test_initializes_with_app_name
      with_env("SCALINGO_API_TOKEN" => "test_token")

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )

      assert_equal @app_name, client.instance_variable_get(:@source_app)
      assert_equal @logger, client.instance_variable_get(:@logger)
      refute_nil client.instance_variable_get(:@client)
    end

    def test_requires_api_token
      with_env("SCALINGO_API_TOKEN" => nil)

      error = assert_raises(ScalingoStagingSync::Integrations::BackupService::BackupError) do
        ScalingoStagingSync::Integrations::ScalingoApiClient.new(
          @app_name,
          logger: @logger
        )
      end

      assert_includes error.message, "SCALINGO_API_TOKEN"
    end

    def test_initializes_scalingo_client
      with_env("SCALINGO_API_TOKEN" => "test_token")

      scalingo_mock = Minitest::Mock.new
      scalingo_mock.expect(:authenticate_with, nil, [], access_token: "test_token")

      Scalingo::Client.stub(:new, scalingo_mock) do
        ScalingoStagingSync::Integrations::ScalingoApiClient.new(
          @app_name,
          logger: @logger
        )

        scalingo_mock.verify
      end
    end
  end

  describe "postgresql_addon_id" do
    def test_finds_postgresql_addon
      with_env("SCALINGO_API_TOKEN" => "test_token")

      pg_addon = { id: "addon-123", addon_provider: { id: "postgresql" } }
      redis_addon = { id: "addon-456", addon_provider: { id: "redis" } }

      addons_response_class = Struct.new(:data)
      region_mock_class = Struct.new(:addons)
      client_mock_class = Struct.new(:osc_fr1)

      addons_response = addons_response_class.new([pg_addon, redis_addon])
      addons_mock = Minitest::Mock.new
      addons_mock.expect(:for, addons_response, [@app_name])

      region_mock = region_mock_class.new(addons_mock)
      client_mock = client_mock_class.new(region_mock)

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )
      client.instance_variable_set(:@client, client_mock)

      result = client.postgresql_addon_id

      assert_equal "addon-123", result
      addons_mock.verify
    end

    def test_raises_when_no_postgresql_addon
      with_env("SCALINGO_API_TOKEN" => "test_token")

      redis_addon = { id: "addon-456", addon_provider: { id: "redis" } }

      addons_response_class = Struct.new(:data)
      region_mock_class = Struct.new(:addons)
      client_mock_class = Struct.new(:osc_fr1)

      addons_response = addons_response_class.new([redis_addon])
      addons_mock = Minitest::Mock.new
      addons_mock.expect(:for, addons_response, [@app_name])

      region_mock = region_mock_class.new(addons_mock)
      client_mock = client_mock_class.new(region_mock)

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )
      client.instance_variable_set(:@client, client_mock)

      error = assert_raises(ScalingoStagingSync::Integrations::BackupService::AddonNotFoundError) do
        client.postgresql_addon_id
      end

      assert_includes error.message, "No PostgreSQL addon found"
      addons_mock.verify
    end
  end

  describe "database_client" do
    def test_creates_database_client
      with_env("SCALINGO_API_TOKEN" => "test_token")

      token_response_class = Struct.new(:data)
      region_mock_class = Struct.new(:addons)

      token_response = token_response_class.new({ token: "db-token-123" })
      addon_mock = Minitest::Mock.new
      addon_mock.expect(:token, token_response, [@app_name, "addon-123"])

      region_mock = region_mock_class.new(addon_mock)

      scalingo_client_mock = Minitest::Mock.new
      scalingo_client_mock.expect(:authenticate_with, true, [], access_token: "test_token")
      scalingo_client_mock.expect(:osc_fr1, region_mock)

      scalingo_config_mock = Minitest::Mock.new
      scalingo_config_mock.expect(:token=, nil, ["db-token-123"])

      api_client_mock = Minitest::Mock.new

      call_count = 0
      client_stub = proc do
        call_count += 1
        call_count == 1 ? scalingo_client_mock : scalingo_config_mock
      end

      Scalingo::Client.stub(:new, client_stub) do
        Scalingo::API::Client.stub(:new, api_client_mock) do
          client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
            @app_name,
            logger: @logger
          )

          client.database_client("addon-123")

          addon_mock.verify
          scalingo_config_mock.verify
          scalingo_client_mock.verify
        end
      end
    end

    def test_raises_when_no_token
      with_env("SCALINGO_API_TOKEN" => "test_token")

      token_response_class = Struct.new(:data)
      region_mock_class = Struct.new(:addons)
      client_mock_class = Struct.new(:osc_fr1)

      token_response = token_response_class.new(nil)
      addon_mock = Minitest::Mock.new
      addon_mock.expect(:token, token_response, [@app_name, "addon-123"])

      region_mock = region_mock_class.new(addon_mock)
      client_mock = client_mock_class.new(region_mock)

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )
      client.instance_variable_set(:@client, client_mock)

      error = assert_raises(ScalingoStagingSync::Integrations::BackupService::BackupError) do
        client.database_client("addon-123")
      end

      assert_includes error.message, "Failed to authenticate with addon"
      addon_mock.verify
    end
  end

  describe "latest_backup" do
    def test_finds_latest_backup
      with_env("SCALINGO_API_TOKEN" => "test_token")

      backup1 = { id: "backup-1", created_at: "2024-01-01T10:00:00Z" }
      backup2 = { id: "backup-2", created_at: "2024-01-02T10:00:00Z" }
      backup3 = { id: "backup-3", created_at: "2024-01-01T15:00:00Z" }

      response_mock_class = Struct.new(:body)
      db_client_class = Struct.new(:authenticated_connection)

      response_body = { database_backups: [backup1, backup2, backup3] }
      response_mock = response_mock_class.new(response_body)

      connection_mock = Minitest::Mock.new
      connection_mock.expect(:get, response_mock, ["https://db-api.osc-fr1.scalingo.com/api/databases/addon-123/backups"])

      db_client = db_client_class.new(connection_mock)

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )

      time_zone_mock = Minitest::Mock.new
      time_zone_mock.expect(:parse, Time.parse("2024-01-01T10:00:00Z"), ["2024-01-01T10:00:00Z"])
      time_zone_mock.expect(:parse, Time.parse("2024-01-02T10:00:00Z"), ["2024-01-02T10:00:00Z"])
      time_zone_mock.expect(:parse, Time.parse("2024-01-01T15:00:00Z"), ["2024-01-01T15:00:00Z"])

      Time.stub(:zone, time_zone_mock) do
        result = client.latest_backup(db_client, "addon-123")

        assert_equal "backup-2", result[:id]
        connection_mock.verify
        time_zone_mock.verify
      end
    end

    def test_raises_when_no_backups
      with_env("SCALINGO_API_TOKEN" => "test_token")

      response_mock_class = Struct.new(:body)
      db_client_class = Struct.new(:authenticated_connection)

      response_body = { database_backups: [] }
      response_mock = response_mock_class.new(response_body)

      connection_mock = Minitest::Mock.new
      connection_mock.expect(:get, response_mock, ["https://db-api.osc-fr1.scalingo.com/api/databases/addon-123/backups"])

      db_client = db_client_class.new(connection_mock)

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )

      error = assert_raises(ScalingoStagingSync::Integrations::BackupService::BackupNotFoundError) do
        client.latest_backup(db_client, "addon-123")
      end

      assert_includes error.message, "No backups found for addon addon-123"
      connection_mock.verify
    end
  end

  describe "backup_download_url" do
    def test_retrieves_download_url
      with_env("SCALINGO_API_TOKEN" => "test_token")

      response_mock_class = Struct.new(:body)
      db_client_class = Struct.new(:authenticated_connection)

      response_body = { download_url: "https://example.com/backup.tar.gz" }
      response_mock = response_mock_class.new(response_body)

      connection_mock = Minitest::Mock.new
      connection_mock.expect(:get, response_mock, ["https://db-api.osc-fr1.scalingo.com/api/databases/addon-123/backups/backup-456/archive"])

      db_client = db_client_class.new(connection_mock)

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )

      result = client.backup_download_url(db_client, "addon-123", "backup-456")

      assert_equal "https://example.com/backup.tar.gz", result
      connection_mock.verify
    end

    def test_raises_when_no_download_url
      with_env("SCALINGO_API_TOKEN" => "test_token")

      response_mock_class = Struct.new(:body)
      db_client_class = Struct.new(:authenticated_connection)

      response_body = { download_url: nil }
      response_mock = response_mock_class.new(response_body)

      connection_mock = Minitest::Mock.new
      connection_mock.expect(:get, response_mock, ["https://db-api.osc-fr1.scalingo.com/api/databases/addon-123/backups/backup-456/archive"])

      db_client = db_client_class.new(connection_mock)

      client = ScalingoStagingSync::Integrations::ScalingoApiClient.new(
        @app_name,
        logger: @logger
      )

      error = assert_raises(ScalingoStagingSync::Integrations::BackupService::DownloadError) do
        client.backup_download_url(db_client, "addon-123", "backup-456")
      end

      assert_includes error.message, "No download URL received"
      connection_mock.verify
    end
  end

  describe "error classes" do
    def test_defines_backup_error_hierarchy
      assert_kind_of Class, ScalingoStagingSync::Integrations::BackupService::BackupError
      assert_kind_of Class, ScalingoStagingSync::Integrations::BackupService::AddonNotFoundError
      assert_kind_of Class, ScalingoStagingSync::Integrations::BackupService::BackupNotFoundError
      assert_kind_of Class, ScalingoStagingSync::Integrations::BackupService::DownloadError

      assert_includes ScalingoStagingSync::Integrations::BackupService::AddonNotFoundError.ancestors, ScalingoStagingSync::Integrations::BackupService::BackupError
    end
  end
end
