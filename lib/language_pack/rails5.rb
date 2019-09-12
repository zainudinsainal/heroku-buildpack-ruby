require 'securerandom'
require "language_pack"
require "language_pack/rails42"

class LanguagePack::Rails5 < LanguagePack::Rails42
  NODE_MODULES_PATH = 'node_modules'
  WEBPACKER_PACKS_PATH = 'public/packs'
  WEBPACKER_CACHE_PATH = 'tmp/cache/webpacker'
  YARN_CACHE_PATH = '~/.yarn-cache'

  # @return [Boolean] true if it's a Rails 5.x app
  def self.use?
    instrument "rails5.use" do
      rails_version = bundler.gem_version('railties')
      return false unless rails_version
      is_rails = rails_version >= Gem::Version.new('5.x') &&
                 rails_version <  Gem::Version.new('6.0.0')
      return is_rails
    end
  end

  def setup_profiled
    instrument 'setup_profiled' do
      super
      set_env_default "RAILS_LOG_TO_STDOUT", "enabled"
    end
  end

  def default_config_vars
    super.merge({
      "RAILS_LOG_TO_STDOUT" => "enabled"
    })
  end

  def install_plugins
    # do not install plugins, do not call super, do not warn
  end

  def config_detect
    super
    @local_storage_config = @rails_runner.detect("active_storage.service")
  end

  def best_practice_warnings
    super
    return unless bundler.has_gem?("activestorage")
    return unless File.exist?("config/storage.yml")

    warn_local_storage if local_storage?
    warn_no_ffmpeg     if needs_ffmpeg?
  end

  private
    def has_ffmpeg?
      run("which ffmpeg")
      return $?.success?
    end

    def needs_ffmpeg?
      !has_ffmpeg?
    end

    def local_storage?
      return false unless @local_storage_config.success?
      @local_storage_config.did_match?("local")
    end

    def warn_local_storage
      mcount("warn.activestorage.local_storage")
      warn(<<-WARNING)
You set your `config.active_storage.service` to :local in production.
If you are uploading files to this app, they will not persist after the app
is restarted, on one-off dynos, or if the app has multiple dynos.
Heroku applications have an ephemeral file system. To
persist uploaded files, please use a service such as S3 and update your Rails
configuration.

For more information can be found in this article:
  https://devcenter.heroku.com/articles/active-storage-on-heroku

WARNING
    end

    def warn_no_ffmpeg
      mcount("warn.activestorage.no_binaries.stack-#{stack}")
      mcount("warn.activestorage.no_binaries.all")
      warn(<<-WARNING)
We detected that some binary dependencies required to
use all the preview features of Active Storage are not
present on this system.

For more information please see:
  https://devcenter.heroku.com/articles/active-storage-on-heroku

WARNING
    end

    def run_assets_precompile_rake_task
      instrument "rails51.run_assets_precompile_rake_task" do
        log("assets_precompile") do
          if Dir.glob("public/assets/{.sprockets-manifest-*.json,manifest-*.json}", File::FNM_DOTMATCH).any?
            puts "Detected manifest file, assuming assets were compiled locally"
            return true
          end

          precompile = rake.task("assets:precompile")
          return true unless precompile.is_defined?

          topic("Preparing app for Rails asset pipeline")

          load_asset_cache

          precompile.invoke(env: rake_env)

          if precompile.success?
            log "assets_precompile", :status => "success"
            puts "Asset precompilation completed (#{"%.2f" % precompile.time}s)"

            puts "Cleaning assets"
            rake.task("assets:clean").invoke(env: rake_env)

            cleanup_assets_cache
            store_asset_cache
          else
            precompile_fail(precompile.output)
          end
        end
      end
    end

    def load_asset_cache
      puts "Loading asset cache"
      @cache.load_without_overwrite public_assets_folder
      @cache.load default_assets_cache
      @cache.load NODE_MODULES_PATH
      @cache.load YARN_CACHE_PATH
      @cache.load WEBPACKER_CACHE_PATH
      @cache.load WEBPACKER_PACKS_PATH
    end

    def store_asset_cache
      puts "Storing asset cache"
      @cache.store public_assets_folder
      @cache.store default_assets_cache
      @cache.store NODE_MODULES_PATH
      @cache.store YARN_CACHE_PATH
      @cache.store WEBPACKER_CACHE_PATH
      @cache.store WEBPACKER_PACKS_PATH
    end

    def cleanup
      # does not call super because it would return if default_assets_cache was missing
      return if assets_compile_enabled?

      puts "Removing non-essential asset cache directories"
      FileUtils.remove_dir(default_assets_cache) if Dir.exist?(default_assets_cache)
      FileUtils.remove_dir(NODE_MODULES_PATH) if Dir.exist?(NODE_MODULES_PATH)
      FileUtils.remove_dir(WEBPACKER_CACHE_PATH) if Dir.exist?(WEBPACKER_CACHE_PATH)
    end
end
