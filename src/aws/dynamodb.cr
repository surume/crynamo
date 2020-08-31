require "./dynamodb/**"

module AWS::DynamoDB
  # Represents the supported AWS DynamoDB operations (note: this is not exhaustive).
  enum Operation
    BatchGetItem
    GetItem
    PutItem
    DeleteItem
    Query
  end
end
