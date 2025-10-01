# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class DatabaseBackupServiceTest < Minitest::Test
  def setup
    super
    stub_rails
    @temp_dir = Dir.mktmpdir("backup_test")
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
    @source_app = "production-app"

    ScalingoStagingSync.configure do |config|
      config.logger = @logger
      config.temp_dir = @temp_dir
    end

    @service = ScalingoStagingSync::Services::DatabaseBackupService.new(
      @source_app,
      @temp_dir,
      logger: @logger
    )
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
    unstub_rails
    super
  end

  describe "initialization" do
    def setup
      super
      stub_rails
      @temp_dir = Dir.mktmpdir("backup_test")
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @source_app = "production-app"
    end

    def test_creates_temp_directory
      temp_dir = File.join(@test_dir, "nonexistent")
      refute_path_exists temp_dir

      ScalingoStagingSync::Services::DatabaseBackupService.new(
        @source_app,
        temp_dir,
        logger: @logger
      )

      assert_path_exists temp_dir
    end

    def test_initializes_dependencies
      service = ScalingoStagingSync::Services::DatabaseBackupService.new(
        @source_app,
        @temp_dir,
        logger: @logger
      )

      assert_equal @source_app, service.instance_variable_get(:@source_app)
      assert_equal @temp_dir, service.instance_variable_get(:@temp_dir)
      assert_equal @logger, service.instance_variable_get(:@logger)
      refute_nil service.instance_variable_get(:@slack_notifier)
      refute_nil service.instance_variable_get(:@api_client)
      refute_nil service.instance_variable_get(:@file_downloader)
    end
  end

  describe "download_and_extract!" do
    def setup
      super
      stub_rails
      @temp_dir = Dir.mktmpdir("backup_test")
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @source_app = "production-app"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.temp_dir = @temp_dir
      end

      @service = ScalingoStagingSync::Services::DatabaseBackupService.new(
        @source_app,
        @temp_dir,
        logger: @logger
      )
    end

    def test_uses_existing_archive_when_present
      # Create a fake existing archive
      existing_archive = File.join(@temp_dir, "backup-2024-01-01-00-00-00.tar.gz")
      File.write(existing_archive, "fake backup data")

      # Mock the extraction
      @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
        result = @service.download_and_extract!

        assert_equal "/path/to/extracted", result

        # Verify no download was attempted
        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Found existing archive, skipping download"
        assert_includes logs, "archive=backup-2024-01-01-00-00-00.tar.gz"
      end
    end

    def test_forces_download_when_flag_set
      # Create existing archive
      existing_archive = File.join(@temp_dir, "backup-2024-01-01-00-00-00.tar.gz")
      File.write(existing_archive, "old backup")

      # Mock the download
      new_archive = File.join(@temp_dir, "backup-new.tar.gz")

      download_stub = proc do
        File.write(new_archive, "new backup data")
        new_archive
      end

      @service.stub(:download_backup_via_api, download_stub) do
        @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
          result = @service.download_and_extract!(force_download: true)

          assert_equal "/path/to/extracted", result

          # Verify old archive was removed
          refute_path_exists existing_archive

          logs = @logger.instance_variable_get(:@logdev).dev.string
          assert_includes logs, "Found existing archive but forcing redownload"
          assert_includes logs, "Removed existing archive"
        end
      end
    end

    def test_downloads_when_no_existing_archive
      # Ensure no archives exist
      Dir.glob(File.join(@temp_dir, "*.tar.gz")).each { |f| File.delete(f) }

      # Mock the API download
      new_archive = File.join(@temp_dir, "backup-new.tar.gz")

      download_stub = proc do
        File.write(new_archive, "new backup data")
        new_archive
      end

      @service.stub(:download_backup_via_api, download_stub) do
        @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
          result = @service.download_and_extract!

          assert_equal "/path/to/extracted", result

          logs = @logger.instance_variable_get(:@logdev).dev.string
          assert_includes logs, "Initiating backup download via Scalingo API"
          assert_includes logs, "Backup download completed"
        end
      end
    end

    def test_handles_download_failure
      # Ensure no archives exist
      Dir.glob(File.join(@temp_dir, "*.tar.gz")).each { |f| File.delete(f) }

      # Mock API to return nil (failure)
      @service.stub(:download_backup_via_api, nil) do
        error = assert_raises(ScalingoStagingSync::Services::DatabaseBackupService::DownloadError) do
          @service.download_and_extract!
        end

        assert_includes error.message, "Failed to download backup from #{@source_app}"
      end
    end

    def test_handles_extraction_failure
      # Create a fake archive
      archive = File.join(@temp_dir, "backup.tar.gz")
      File.write(archive, "fake data")

      # Mock extraction to raise error
      @service.stub(:extract_and_prepare_backup, proc { raise "Extraction failed" }) do
        error = assert_raises(RuntimeError) do
          @service.download_and_extract!
        end

        assert_equal "Extraction failed", error.message
      end
    end

    def test_respects_force_env_variable
      with_env("FORCE_BACKUP_DOWNLOAD" => "true")

      # Create existing archive
      existing_archive = File.join(@temp_dir, "backup-old.tar.gz")
      File.write(existing_archive, "old backup")

      new_archive = File.join(@temp_dir, "backup-new.tar.gz")

      download_stub = proc do
        File.write(new_archive, "new backup data")
        new_archive
      end

      @service.stub(:download_backup_via_api, download_stub) do
        @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
          result = @service.download_and_extract!

          assert_equal "/path/to/extracted", result

          # Old archive should be removed
          refute_path_exists existing_archive
        end
      end
    end
  end

  describe "archive handling" do
    def setup
      super
      stub_rails
      @temp_dir = Dir.mktmpdir("backup_test")
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @source_app = "production-app"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.temp_dir = @temp_dir
      end

      @service = ScalingoStagingSync::Services::DatabaseBackupService.new(
        @source_app,
        @temp_dir,
        logger: @logger
      )
    end

    def test_finds_latest_archive
      # Create multiple archives with different timestamps
      archive1 = File.join(@temp_dir, "backup-2024-01-01-00-00-00.tar.gz")
      archive2 = File.join(@temp_dir, "backup-2024-01-02-00-00-00.tar.gz")
      archive3 = File.join(@temp_dir, "backup-2024-01-03-00-00-00.tar.gz")

      File.write(archive1, "data1")
      File.write(archive2, "data2")
      File.write(archive3, "data3")

      # Set modification times to ensure order
      FileUtils.touch(archive1, mtime: Time.new(2024, 1, 1))
      FileUtils.touch(archive2, mtime: Time.new(2024, 1, 2))
      FileUtils.touch(archive3, mtime: Time.new(2024, 1, 3))

      latest = Dir.chdir(@temp_dir) { @service.send(:find_latest_archive) }
      assert_equal File.basename(archive3), latest
    end

    def test_returns_nil_when_no_archives
      Dir.glob(File.join(@temp_dir, "*.tar.gz")).each { |f| File.delete(f) }

      latest = Dir.chdir(@temp_dir) { @service.send(:find_latest_archive) }
      assert_nil latest
    end

    def test_extract_and_prepare_backup
      # Create a real tar.gz file with a dump inside
      dump_file = File.join(@temp_dir, "test.pgsql")
      File.write(dump_file, "-- PostgreSQL database dump\nSELECT 1;")

      archive_file = File.join(@temp_dir, "backup.tar.gz")

      # Create tar.gz archive
      Dir.chdir(@temp_dir) do
        system("tar -czf backup.tar.gz test.pgsql", out: File::NULL, err: File::NULL)
      end

      FileUtils.rm_f(dump_file)

      # Test extraction - must be run in temp_dir context
      result = Dir.chdir(@temp_dir) { @service.send(:extract_and_prepare_backup, File.basename(archive_file)) }

      # Should return path to extracted dump
      assert_path_exists result
      assert_includes File.read(result), "PostgreSQL database dump"
    end

    def test_handles_corrupt_archive
      # Create a corrupt archive
      archive = File.join(@temp_dir, "corrupt.tar.gz")
      File.write(archive, "not a valid tar.gz file")

      assert_raises(RuntimeError) do
        Dir.chdir(@temp_dir) { @service.send(:extract_and_prepare_backup, File.basename(archive)) }
      end
    end
  end

  describe "error handling and retries" do
    def setup
      super
      stub_rails
      @temp_dir = Dir.mktmpdir("backup_test")
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @source_app = "production-app"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.temp_dir = @temp_dir
      end

      @service = ScalingoStagingSync::Services::DatabaseBackupService.new(
        @source_app,
        @temp_dir,
        logger: @logger
      )
    end

    def test_retries_download_on_failure
      # Ensure no archives exist
      Dir.glob(File.join(@temp_dir, "*.tar.gz")).each { |f| File.delete(f) }

      attempts = 0
      backup_file = File.join(@temp_dir, "backup.tar.gz")

      @service.stub(
        :download_backup_via_api,
        proc do
          attempts += 1
          raise "Connection timeout error" if attempts < 3

          File.write(backup_file, "data")
          backup_file
        end
      ) do
        @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
          result = @service.download_and_extract!

          assert_equal "/path/to/extracted", result
          assert_equal 3, attempts

          logs = @logger.instance_variable_get(:@logdev).dev.string
          assert_includes logs, "Retrying"
        end
      end
    end

    def test_gives_up_after_max_retries
      attempts = 0

      @service.stub(
        :download_backup_via_api,
        proc do
          attempts += 1
          raise "Connection timeout error"
        end
      ) do
        assert_raises(RuntimeError) do
          @service.download_and_extract!
        end

        assert_equal 3, attempts
      end
    end
  end

  describe "slack notifications" do
    def setup
      super
      stub_rails
      @temp_dir = Dir.mktmpdir("backup_test")
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @source_app = "production-app"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.temp_dir = @temp_dir
      end

      @service = ScalingoStagingSync::Services::DatabaseBackupService.new(
        @source_app,
        @temp_dir,
        logger: @logger
      )
    end

    def test_sends_notifications_during_process
      slack_notifier = Minitest::Mock.new
      slack_notifier.expect(:backup_step, nil, ["📦 Téléchargement de la sauvegarde depuis #{@source_app}..."])
      slack_notifier.expect(:backup_step, nil, ["✅ Sauvegarde prête"])

      @service.instance_variable_set(:@slack_notifier, slack_notifier)

      # Mock successful download
      archive = File.join(@temp_dir, "backup.tar.gz")
      File.write(archive, "data")

      @service.stub(:get_or_download_archive, archive) do
        @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
          @service.download_and_extract!

          slack_notifier.verify
        end
      end
    end

    def test_sends_error_notification_on_failure
      slack_notifier = Minitest::Mock.new
      slack_notifier.expect(:backup_step, nil, [String])
      slack_notifier.expect(:backup_step, nil, [String])
      slack_notifier.expect(:backup_error, nil, [String])

      @service.instance_variable_set(:@slack_notifier, slack_notifier)

      @service.stub(:download_backup_via_api, nil) do
        assert_raises(ScalingoStagingSync::Services::DatabaseBackupService::DownloadError) do
          @service.download_and_extract!
        end

        slack_notifier.verify
      end
    end
  end

  describe "logging" do
    def setup
      super
      stub_rails
      @temp_dir = Dir.mktmpdir("backup_test")
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @source_app = "production-app"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.temp_dir = @temp_dir
      end

      @service = ScalingoStagingSync::Services::DatabaseBackupService.new(
        @source_app,
        @temp_dir,
        logger: @logger
      )
    end

    def test_logs_process_steps
      archive = File.join(@temp_dir, "backup.tar.gz")
      File.write(archive, "data")

      @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
        @service.download_and_extract!

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Starting download_and_extract process"
        assert_includes logs, "Found existing archive, skipping download"
        assert_includes logs, "Download and extraction completed successfully"
      end
    end

    def test_logs_file_sizes
      archive = File.join(@temp_dir, "backup.tar.gz")
      File.write(archive, "a" * 1024) # 1KB file

      @service.stub(:extract_and_prepare_backup, "/path/to/extracted") do
        @service.download_and_extract!

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "1.0KB" # Formatted file size
      end
    end
  end
end
