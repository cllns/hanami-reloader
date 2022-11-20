# frozen_string_literal: true

module Hanami
  module Reloader
    module Commands
      # Guardfile
      module Guardfile
        def self.group
          "server"
        end

        def self.default_path
          path("Guardfile")
        end

        def self.path(value)
          value
        end
      end

      # Generate hanami-reloader configuration
      class Install < Hanami::CLI::Command
        desc "Generate configuration for code reloading"

        def initialize(fs: Dry::Files.new, bundler: CLI::Bundler.new(fs: fs), **args)
          super(fs: fs, **args)
          @bundler = bundler
        end

        def call(*, **)
          generate_configuration(Guardfile.default_path)
          bundle_gems
        end

        private

        attr_reader :bundler

        def generate_configuration(path)
          fs.write path, <<~CODE
            # frozen_string_literal: true

            group :#{Guardfile.group} do
              guard "puma", port: ENV["HANAMI_PORT"] || 2300 do
                watch(%r{config/*})
                watch(%r{lib/*})
                watch(%r{app/*})
                watch(%r{slices/*})
              end
            end
          CODE
        end

        def bundle_gems
          fs.touch("Gemfile")
          gemfile = fs.read("Gemfile")

          return if gemfile.include?("guard-puma")

          if gemfile.include?("group :development do")
            fs.inject_line_at_block_bottom "Gemfile", "group :development do", <<~CODE
              gem "guard-puma"
            CODE
          else
            fs.append "Gemfile", <<~CODE

              group :development do
                gem "guard-puma", "~> 0.8"
              end
            CODE
          end

          bundler.install!
        end
      end

      # Override `hanami server` command
      class Server < Hanami::CLI::Commands::App::Server
        # @since 2.0.0
        # @api private
        DEFAULT_GUARD_PUMA_OPTIONS = ["-n", "f", "-i", "-g", Guardfile.group, "-G"].freeze

        # @since 2.0.0
        # @api private
        OPTIONS_SEPARATOR = " "

        option :guardfile,      type: :string,  desc: "Path to Guardfile", default: Guardfile.default_path.to_s
        option :code_reloading, type: :boolean, desc: "Code reloading",    default: true

        desc "Start Hanami app server"

        example [
          "--no-code-reloading # Disable code reloading"
        ]

        def call(**args)
          code_reloading = args.fetch(:code_reloading)

          if code_reloading
            guard_puma_env_vars!(**args)
            exec "bundle exec guard #{guard_puma_options(**args)}"
          else
            super
          end
        end

        private

        def guard_puma_env_vars!(**args)
          ENV["HANAMI_PORT"] = args.fetch(:port).to_s
        end

        def guard_puma_options(**args)
          options = DEFAULT_GUARD_PUMA_OPTIONS.dup
          options.push(Guardfile.path(args.fetch(:guardfile)))
          options.join(OPTIONS_SEPARATOR)
        end
      end
    end
  end
end
