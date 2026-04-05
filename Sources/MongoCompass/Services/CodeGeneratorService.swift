import Foundation

// MARK: - Code Language

enum CodeLanguage: String, CaseIterable {
    case python
    case javascript
    case java
    case go
    case csharp

    var displayName: String {
        switch self {
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .java: return "Java"
        case .go: return "Go"
        case .csharp: return "C#"
        }
    }
}

// MARK: - CodeGeneratorService

struct CodeGeneratorService {

    // MARK: - Find Code Generation

    func generateFindCode(
        database: String,
        collection: String,
        filter: String,
        sort: String,
        projection: String,
        skip: Int,
        limit: Int,
        language: CodeLanguage
    ) -> String {
        let filterStr = filter.isEmpty ? "{}" : filter
        let sortStr = sort.isEmpty ? "" : sort
        let projStr = projection.isEmpty ? "" : projection

        switch language {
        case .python:
            return generatePythonFind(database: database, collection: collection, filter: filterStr, sort: sortStr, projection: projStr, skip: skip, limit: limit)
        case .javascript:
            return generateJSFind(database: database, collection: collection, filter: filterStr, sort: sortStr, projection: projStr, skip: skip, limit: limit)
        case .java:
            return generateJavaFind(database: database, collection: collection, filter: filterStr, sort: sortStr, projection: projStr, skip: skip, limit: limit)
        case .go:
            return generateGoFind(database: database, collection: collection, filter: filterStr, sort: sortStr, projection: projStr, skip: skip, limit: limit)
        case .csharp:
            return generateCSharpFind(database: database, collection: collection, filter: filterStr, sort: sortStr, projection: projStr, skip: skip, limit: limit)
        }
    }

    // MARK: - Aggregation Code Generation

    func generateAggregationCode(
        database: String,
        collection: String,
        pipeline: String,
        language: CodeLanguage
    ) -> String {
        let pipelineStr = pipeline.isEmpty ? "[]" : pipeline

        switch language {
        case .python:
            return generatePythonAggregation(database: database, collection: collection, pipeline: pipelineStr)
        case .javascript:
            return generateJSAggregation(database: database, collection: collection, pipeline: pipelineStr)
        case .java:
            return generateJavaAggregation(database: database, collection: collection, pipeline: pipelineStr)
        case .go:
            return generateGoAggregation(database: database, collection: collection, pipeline: pipelineStr)
        case .csharp:
            return generateCSharpAggregation(database: database, collection: collection, pipeline: pipelineStr)
        }
    }

    // MARK: - Python

    private func generatePythonFind(database: String, collection: String, filter: String, sort: String, projection: String, skip: Int, limit: Int) -> String {
        var code = """
        from pymongo import MongoClient

        client = MongoClient("mongodb://localhost:27017")
        db = client["\(database)"]
        collection = db["\(collection)"]

        cursor = collection.find(\(filter))
        """

        if !sort.isEmpty {
            code += "\ncursor = cursor.sort(\(sort))"
        }
        if !projection.isEmpty {
            // Re-generate with projection parameter
            code = """
            from pymongo import MongoClient

            client = MongoClient("mongodb://localhost:27017")
            db = client["\(database)"]
            collection = db["\(collection)"]

            cursor = collection.find(\(filter), \(projection))
            """
            if !sort.isEmpty {
                code += "\ncursor = cursor.sort(\(sort))"
            }
        }
        if skip > 0 {
            code += "\ncursor = cursor.skip(\(skip))"
        }
        if limit > 0 {
            code += "\ncursor = cursor.limit(\(limit))"
        }
        code += "\n\nfor doc in cursor:\n    print(doc)"
        return code
    }

    private func generatePythonAggregation(database: String, collection: String, pipeline: String) -> String {
        return """
        from pymongo import MongoClient

        client = MongoClient("mongodb://localhost:27017")
        db = client["\(database)"]
        collection = db["\(collection)"]

        pipeline = \(pipeline)

        results = collection.aggregate(pipeline)

        for doc in results:
            print(doc)
        """
    }

    // MARK: - JavaScript (Node.js)

    private func generateJSFind(database: String, collection: String, filter: String, sort: String, projection: String, skip: Int, limit: Int) -> String {
        var queryChain = "  const cursor = collection.find(\(filter))"

        if !projection.isEmpty {
            queryChain += "\n    .project(\(projection))"
        }
        if !sort.isEmpty {
            queryChain += "\n    .sort(\(sort))"
        }
        if skip > 0 {
            queryChain += "\n    .skip(\(skip))"
        }
        if limit > 0 {
            queryChain += "\n    .limit(\(limit))"
        }
        queryChain += ";"

        return """
        const { MongoClient } = require("mongodb");

        async function main() {
          const client = new MongoClient("mongodb://localhost:27017");
          await client.connect();

          const db = client.db("\(database)");
          const collection = db.collection("\(collection)");

        \(queryChain)

          const results = await cursor.toArray();
          console.log(results);

          await client.close();
        }

        main().catch(console.error);
        """
    }

    private func generateJSAggregation(database: String, collection: String, pipeline: String) -> String {
        return """
        const { MongoClient } = require("mongodb");

        async function main() {
          const client = new MongoClient("mongodb://localhost:27017");
          await client.connect();

          const db = client.db("\(database)");
          const collection = db.collection("\(collection)");

          const pipeline = \(pipeline);

          const results = await collection.aggregate(pipeline).toArray();
          console.log(results);

          await client.close();
        }

        main().catch(console.error);
        """
    }

    // MARK: - Java

    private func generateJavaFind(database: String, collection: String, filter: String, sort: String, projection: String, skip: Int, limit: Int) -> String {
        var imports = """
        import com.mongodb.client.MongoClient;
        import com.mongodb.client.MongoClients;
        import com.mongodb.client.MongoCollection;
        import com.mongodb.client.MongoDatabase;
        import com.mongodb.client.FindIterable;
        import org.bson.Document;
        """

        var body = """

        public class MongoQuery {
            public static void main(String[] args) {
                MongoClient client = MongoClients.create("mongodb://localhost:27017");
                MongoDatabase db = client.getDatabase("\(database)");
                MongoCollection<Document> collection = db.getCollection("\(collection)");

                FindIterable<Document> cursor = collection
                    .find(Document.parse("\(escapeJavaString(filter))"))
        """

        if !sort.isEmpty {
            body += "\n            .sort(Document.parse(\"\(escapeJavaString(sort))\"))"
        }
        if !projection.isEmpty {
            body += "\n            .projection(Document.parse(\"\(escapeJavaString(projection))\"))"
        }
        if skip > 0 {
            body += "\n            .skip(\(skip))"
        }
        if limit > 0 {
            body += "\n            .limit(\(limit))"
        }
        body += ";"

        body += """

                for (Document doc : cursor) {
                    System.out.println(doc.toJson());
                }

                client.close();
            }
        }
        """

        return imports + body
    }

    private func generateJavaAggregation(database: String, collection: String, pipeline: String) -> String {
        return """
        import com.mongodb.client.MongoClient;
        import com.mongodb.client.MongoClients;
        import com.mongodb.client.MongoCollection;
        import com.mongodb.client.MongoDatabase;
        import com.mongodb.client.AggregateIterable;
        import org.bson.Document;
        import java.util.Arrays;
        import java.util.List;

        public class MongoAggregation {
            public static void main(String[] args) {
                MongoClient client = MongoClients.create("mongodb://localhost:27017");
                MongoDatabase db = client.getDatabase("\(database)");
                MongoCollection<Document> collection = db.getCollection("\(collection)");

                // Note: Parse each stage from the pipeline JSON array
                String pipelineJson = "\(escapeJavaString(pipeline))";
                List<Document> pipeline = Document.parse("{stages: " + pipelineJson + "}")
                    .getList("stages", Document.class);

                AggregateIterable<Document> results = collection.aggregate(pipeline);

                for (Document doc : results) {
                    System.out.println(doc.toJson());
                }

                client.close();
            }
        }
        """
    }

    // MARK: - Go

    private func generateGoFind(database: String, collection: String, filter: String, sort: String, projection: String, skip: Int, limit: Int) -> String {
        var optionLines = ""
        if !sort.isEmpty {
            optionLines += "\topts.SetSort(bson.D{})\n\t// Sort: \(sort)\n"
        }
        if !projection.isEmpty {
            optionLines += "\topts.SetProjection(bson.D{})\n\t// Projection: \(projection)\n"
        }
        if skip > 0 {
            optionLines += "\topts.SetSkip(int64(\(skip)))\n"
        }
        if limit > 0 {
            optionLines += "\topts.SetLimit(int64(\(limit)))\n"
        }

        return """
        package main

        import (
        \t"context"
        \t"fmt"
        \t"log"

        \t"go.mongodb.org/mongo-driver/bson"
        \t"go.mongodb.org/mongo-driver/mongo"
        \t"go.mongodb.org/mongo-driver/mongo/options"
        )

        func main() {
        \tclient, err := mongo.Connect(context.TODO(), options.Client().ApplyURI("mongodb://localhost:27017"))
        \tif err != nil {
        \t\tlog.Fatal(err)
        \t}
        \tdefer client.Disconnect(context.TODO())

        \tcollection := client.Database("\(database)").Collection("\(collection)")

        \t// Filter: \(filter)
        \tfilter := bson.D{}

        \topts := options.Find()
        \(optionLines)
        \tcursor, err := collection.Find(context.TODO(), filter, opts)
        \tif err != nil {
        \t\tlog.Fatal(err)
        \t}
        \tdefer cursor.Close(context.TODO())

        \tvar results []bson.M
        \tif err := cursor.All(context.TODO(), &results); err != nil {
        \t\tlog.Fatal(err)
        \t}

        \tfor _, result := range results {
        \t\tfmt.Println(result)
        \t}
        }
        """
    }

    private func generateGoAggregation(database: String, collection: String, pipeline: String) -> String {
        return """
        package main

        import (
        \t"context"
        \t"fmt"
        \t"log"

        \t"go.mongodb.org/mongo-driver/bson"
        \t"go.mongodb.org/mongo-driver/mongo"
        \t"go.mongodb.org/mongo-driver/mongo/options"
        )

        func main() {
        \tclient, err := mongo.Connect(context.TODO(), options.Client().ApplyURI("mongodb://localhost:27017"))
        \tif err != nil {
        \t\tlog.Fatal(err)
        \t}
        \tdefer client.Disconnect(context.TODO())

        \tcollection := client.Database("\(database)").Collection("\(collection)")

        \t// Pipeline: \(pipeline)
        \tpipeline := mongo.Pipeline{}

        \tcursor, err := collection.Aggregate(context.TODO(), pipeline)
        \tif err != nil {
        \t\tlog.Fatal(err)
        \t}
        \tdefer cursor.Close(context.TODO())

        \tvar results []bson.M
        \tif err := cursor.All(context.TODO(), &results); err != nil {
        \t\tlog.Fatal(err)
        \t}

        \tfor _, result := range results {
        \t\tfmt.Println(result)
        \t}
        }
        """
    }

    // MARK: - C#

    private func generateCSharpFind(database: String, collection: String, filter: String, sort: String, projection: String, skip: Int, limit: Int) -> String {
        var findOptions = ""
        if !sort.isEmpty {
            findOptions += "    Sort = BsonDocument.Parse(\"\(escapeCSharpString(sort))\"),\n"
        }
        if !projection.isEmpty {
            findOptions += "    Projection = BsonDocument.Parse(\"\(escapeCSharpString(projection))\"),\n"
        }
        if skip > 0 {
            findOptions += "    Skip = \(skip),\n"
        }
        if limit > 0 {
            findOptions += "    Limit = \(limit),\n"
        }

        let optionsBlock: String
        if findOptions.isEmpty {
            optionsBlock = ""
        } else {
            optionsBlock = """

                var options = new FindOptions<BsonDocument>
                {
                \(findOptions)};
            """
        }

        let findCall = findOptions.isEmpty
            ? "var cursor = await collection.FindAsync(filter);"
            : "var cursor = await collection.FindAsync(filter, options);"

        return """
        using MongoDB.Bson;
        using MongoDB.Driver;
        using System;
        using System.Threading.Tasks;

        class Program
        {
            static async Task Main(string[] args)
            {
                var client = new MongoClient("mongodb://localhost:27017");
                var db = client.GetDatabase("\(database)");
                var collection = db.GetCollection<BsonDocument>("\(collection)");

                var filter = BsonDocument.Parse("\(escapeCSharpString(filter))");\(optionsBlock)

                \(findCall)

                while (await cursor.MoveNextAsync())
                {
                    foreach (var doc in cursor.Current)
                    {
                        Console.WriteLine(doc.ToJson());
                    }
                }
            }
        }
        """
    }

    private func generateCSharpAggregation(database: String, collection: String, pipeline: String) -> String {
        return """
        using MongoDB.Bson;
        using MongoDB.Bson.Serialization;
        using MongoDB.Driver;
        using System;
        using System.Collections.Generic;
        using System.Threading.Tasks;

        class Program
        {
            static async Task Main(string[] args)
            {
                var client = new MongoClient("mongodb://localhost:27017");
                var db = client.GetDatabase("\(database)");
                var collection = db.GetCollection<BsonDocument>("\(collection)");

                // Pipeline: \(escapeCSharpString(pipeline))
                var pipelineDefinition = PipelineDefinition<BsonDocument, BsonDocument>.Create(
                    BsonSerializer.Deserialize<BsonArray>("\(escapeCSharpString(pipeline))")
                        .Select(s => (BsonDocument)s)
                );

                var results = await collection.AggregateAsync(pipelineDefinition);

                while (await results.MoveNextAsync())
                {
                    foreach (var doc in results.Current)
                    {
                        Console.WriteLine(doc.ToJson());
                    }
                }
            }
        }
        """
    }

    // MARK: - String Escape Helpers

    private func escapeJavaString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func escapeCSharpString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
