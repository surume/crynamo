require "json"
require "../aws/dynamodb"

module Crynamo
  module Marshaller
    extend self

    alias DynamoDB = AWS::DynamoDB

    alias Number = Int8 |
                   Int16 |
                   Int32 |
                   Int64 |
                   Float32 |
                   Float64

    class MarshallException < Exception
    end

    def dynamodb_value_map(value)
      case value
        when Nil
          {DynamoDB::TypeDescriptor.null => true}
        when AWS::DynamoDB::DDB::KeyConditionExpression
          dynamodb_value_map(value.value)
        when String
          {DynamoDB::TypeDescriptor.string => value}
        when Number
          {DynamoDB::TypeDescriptor.number => value.to_s}
        when Bool
          {DynamoDB::TypeDescriptor.bool => value}
        when Array(String)
          {DynamoDB::TypeDescriptor.string_set => value}
        when Array(Int8), Array(Int16), Array(Int32), Array(Int64), Array(Float32), Array(Float64)
          {DynamoDB::TypeDescriptor.number_set => value.map(&.to_s)}
        when Array, Tuple
          {DynamoDB::TypeDescriptor.list => value}
        when NamedTuple
          inner_values = value.to_h.select { |k, v|
            !v.nil?
          }.map { |k, v|
            { k => dynamodb_value_map(v) }
          }.reduce { |acc, v| acc.merge(v) }
          {DynamoDB::TypeDescriptor.map => inner_values}
        when Hash
          inner_values = value.select { |k, v|
            !v.nil?
          }.map { |k, v|
            { k => dynamodb_value_map(v) }
          }.reduce { |acc, v| acc.merge(v) }
          {DynamoDB::TypeDescriptor.map => inner_values}
        else
          raise MarshallException.new "Couldn't marshal Crystal type #{typeof(value)} to DynamoDB type"
        end
    end

    # Converts a `NamedTuple` to a DynamoDB `Hash` representation
    def to_dynamo(tuple : NamedTuple) : Hash
      hash = tuple.to_h
      keys = Array(Symbol).new

      dynamodb_values = hash.select { |k, v|
        case v
        when Nil
          false
        when ""
          false
        when Array
          v.size > 0
        else
          true
        end
      }.map do |k, v|
        keys.push(k)
        dynamodb_value_map(v)
      end

      Hash.zip(keys, dynamodb_values)
    end

    # { product_id: product.id }
    def to_expressions(tuple : NamedTuple)# : Tuple(String, Hash(String, Hash(String, String | Hash(String, String) | Hash(String, Bool))))
      key_condition_expression = tuple.keys.to_a.map do |key|
        v = tuple[key]
        case v
        when AWS::DynamoDB::DDB::KeyConditionExpression
          s = v.condition
          "#{key} #{s} :#{key}"
        else
          "#{key} = :#{key}"
        end
      end.join(" AND ")

      expression_attribute_values = {} of String => Hash(String, Bool) | Hash(String, String)

      # unwrap value in key condition tuple

      marshalled = to_dynamo(tuple)
      marshalled.each do |key, value|
        case value
        when Nil
        when AWS::DynamoDB::DDB::KeyConditionExpression
          expression_attribute_values[":#{key}"] = value.value
        else
          expression_attribute_values[":#{key}"] = value
        end
      end

      {key_condition_expression, expression_attribute_values}
    end

    # Converts a DynamoDB `Hash` representation to a regular Crystal `Hash`
    # TODO Convert to a `NamedTuple` instead
    def from_dynamo(item : Hash(String, JSON::Any)) : Hash
      keys = item.keys

      crystal_values = item.values.map do |value|
        dynamodb_type = value.as_h.first_key
        dynamodb_value = value.as_h.first_value

        case dynamodb_type
        when DynamoDB::TypeDescriptor.string
          dynamodb_value
        when DynamoDB::TypeDescriptor.number
          dynamodb_value.as_s.to_f32
        when DynamoDB::TypeDescriptor.bool
          dynamodb_value.as_bool
        when DynamoDB::TypeDescriptor.string_set
          dynamodb_value
            .as_a
            .map(&.as_s)
        when DynamoDB::TypeDescriptor.number_set
          dynamodb_value
            .as_a
            .map(&.as_s.to_f32)
        when DynamoDB::TypeDescriptor.list
          dynamodb_value.as_a
        when DynamoDB::TypeDescriptor.map
          # TODO Figure out what we need to do to cast to a generic Hash or NamedTuple
          # dynamodb_value.as(Hash(String, JSON::Type))
          # dynamodb_value.as(Hash)
          # JSON.parse(dynamodb_value.as(String)).as_h
          # dynamodb_value.as(NamedTuple)
          dynamodb_value
        when DynamoDB::TypeDescriptor.null
          nil
        else
          raise MarshallException.new "Couldn't marshal DynamoDB type #{typeof(dynamodb_type)} to Crystal type."
        end
      end

      Hash.zip(keys, crystal_values)
    end

    def from_dynamo(items : Array(Hash)) : Array(Hash(String, Array(Float32) | Array(JSON::Any) | Array(String) | Number | Bool | Float32 | JSON::Any | Nil))
      items.map{ |item| from_dynamo(item) } unless items.nil?
    end
  end
end
