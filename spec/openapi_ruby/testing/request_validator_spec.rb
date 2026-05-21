# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenapiRuby::Testing::RequestValidator do
  def build_operation(params: [], request_body: nil)
    op = OpenapiRuby::DSL::OperationContext.new(:post, "Test")
    params.each { |p| op.parameter(p) }
    op.request_body(request_body) if request_body
    op
  end

  def build_path_context(params: [])
    ctx = OpenapiRuby::DSL::Context.new("/test")
    params.each { |p| ctx.parameter(p) }
    ctx
  end

  describe "#validate" do
    it "returns no errors for a valid request" do
      operation = build_operation(
        params: [{name: :page, in: :query, schema: {type: :integer}}]
      )

      errors = described_class.new.validate(
        operation: operation,
        params: {page: 1}
      )

      expect(errors).to be_empty
    end

    it "returns error for missing required query parameter" do
      operation = build_operation(
        params: [{name: :page, in: :query, schema: {type: :integer}, required: true}]
      )

      errors = described_class.new.validate(
        operation: operation,
        params: {}
      )

      expect(errors).to include(/Missing required query parameter: page/)
    end

    it "returns error for missing required path parameter" do
      path_ctx = build_path_context(
        params: [{name: :id, in: :path, schema: {type: :integer}}]
      )

      operation = build_operation

      errors = described_class.new.validate(
        operation: operation,
        path_context: path_ctx,
        path_params: {}
      )

      # Path params are auto-required by the DSL
      expect(errors).to include(/Missing required path parameter: id/)
    end

    it "returns error for parameter type mismatch" do
      operation = build_operation(
        params: [{name: :page, in: :query, schema: {type: :integer}}]
      )

      errors = described_class.new.validate(
        operation: operation,
        params: {page: "not_a_number"}
      )

      expect(errors).to include(/Invalid query parameter 'page'/)
    end

    it "coerces string integers for parameter validation" do
      operation = build_operation(
        params: [{name: :page, in: :query, schema: {type: :integer}}]
      )

      errors = described_class.new.validate(
        operation: operation,
        params: {page: "3"}
      )

      expect(errors).to be_empty
    end

    it "returns error when required request body is missing" do
      operation = build_operation(
        request_body: {
          required: true,
          content: {"application/json" => {schema: {type: :object}}}
        }
      )

      errors = described_class.new.validate(
        operation: operation,
        body: nil
      )

      expect(errors).to include("Request body is required")
    end

    it "returns error for request body missing required fields" do
      operation = build_operation(
        request_body: {
          required: true,
          content: {
            "application/json" => {
              schema: {
                type: :object,
                required: ["title"],
                properties: {title: {type: :string}}
              }
            }
          }
        }
      )

      errors = described_class.new.validate(
        operation: operation,
        body: {name: "test"}
      )

      expect(errors.length).to be > 0
      expect(errors.first).to include("request body")
    end

    it "returns no errors when request body matches schema" do
      operation = build_operation(
        request_body: {
          required: true,
          content: {
            "application/json" => {
              schema: {
                type: :object,
                required: ["title"],
                properties: {title: {type: :string}}
              }
            }
          }
        }
      )

      errors = described_class.new.validate(
        operation: operation,
        body: {"title" => "Hello"}
      )

      expect(errors).to be_empty
    end

    it "skips validation when no parameters or body defined" do
      operation = build_operation

      errors = described_class.new.validate(
        operation: operation,
        params: {anything: "goes"}
      )

      expect(errors).to be_empty
    end

    it "skips $ref schema validation without document" do
      operation = build_operation(
        request_body: {
          required: true,
          content: {
            "application/json" => {
              schema: {"$ref" => "#/components/schemas/Post"}
            }
          }
        }
      )

      errors = described_class.new.validate(
        operation: operation,
        body: {title: "test"}
      )

      # Should not error — $ref cannot be resolved without document
      expect(errors).to be_empty
    end

    it "validates $ref schema when document is provided" do
      document = {
        "openapi" => "3.1.0",
        "info" => {"title" => "Test", "version" => "1.0"},
        "paths" => {},
        "components" => {
          "schemas" => {
            "Post" => {
              "type" => "object",
              "required" => ["title"],
              "properties" => {
                "title" => {"type" => "string", "minLength" => 1}
              }
            }
          }
        }
      }

      operation = build_operation(
        request_body: {
          required: true,
          content: {
            "application/json" => {
              schema: {"$ref" => "#/components/schemas/Post"}
            }
          }
        }
      )

      validator = described_class.new(document)

      # Valid body
      errors = validator.validate(operation: operation, body: {"title" => "Hello"})
      expect(errors).to be_empty

      # Invalid body (empty title)
      errors = validator.validate(operation: operation, body: {"title" => ""})
      expect(errors.length).to be > 0
      expect(errors.first).to include("request body")
    end
  end
end
