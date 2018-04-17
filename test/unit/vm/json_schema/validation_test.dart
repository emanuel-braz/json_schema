// Copyright 2013-2018 Workiva Inc.
//
// Licensed under the Boost Software License (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.boost.org/LICENSE_1_0.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This software or document includes material copied from or derived
// from JSON-Schema-Test-Suite (https://github.com/json-schema-org/JSON-Schema-Test-Suite),
// Copyright (c) 2012 Julian Berman, which is licensed under the following terms:
//
//     Copyright (c) 2012 Julian Berman
//
//     Permission is hereby granted, free of charge, to any person obtaining a copy
//     of this software and associated documentation files (the "Software"), to deal
//     in the Software without restriction, including without limitation the rights
//     to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//     copies of the Software, and to permit persons to whom the Software is
//     furnished to do so, subject to the following conditions:
//
//     The above copyright notice and this permission notice shall be included in
//     all copies or substantial portions of the Software.
//
//     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//     OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//     THE SOFTWARE.

library json_schema.test_validation;

import 'dart:convert' as convert;
import 'dart:io';
import 'package:json_schema/json_schema.dart';
import 'package:json_schema/vm.dart';
import 'package:json_schema/src/json_schema/constants.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:test/test.dart';

final Logger _logger = new Logger('test_validation');

void main([List<String> args]) {
  configureJsonSchemaForVm();

  // Serve remotes for ref tests.
  final specFileHandler = createStaticHandler('test/JSON-Schema-Test-Suite/remotes');
  io.serve(specFileHandler, 'localhost', 1234);

  final additionalRemotesHandler = createStaticHandler('test/additional_remotes');
  io.serve(additionalRemotesHandler, 'localhost', 4321);

  if (args?.isEmpty == true) {
    Logger.root.onRecord.listen((LogRecord r) => print('${r.loggerName} [${r.level}]:\t${r.message}'));
    Logger.root.level = Level.OFF;
  }

  ////////////////////////////////////////////////////////////////////////
  // Uncomment to see logging of exceptions
  // Logger.root.onRecord.listen((LogRecord r) =>
  //   print('${r.loggerName} [${r.level}]:\t${r.message}'));

  Logger.root.level = Level.OFF;

  // Directory testSuiteFolder = new Directory('./test/JSON-Schema-Test-Suite/tests/draft6/invalidSchemas');

  // Draft 4 Tests
  final Directory testSuiteFolderV4 = new Directory('./test/JSON-Schema-Test-Suite/tests/draft4');
  final Directory optionalsV4 = new Directory(path.joinAll([testSuiteFolderV4.path, 'optional']));
  final allDraft4 = testSuiteFolderV4.listSync()..addAll(optionalsV4.listSync());

  // Draft 6 Tests
  final Directory testSuiteFolderV6 = new Directory('./test/JSON-Schema-Test-Suite/tests/draft6');
  final Directory optionalsV6 = new Directory(path.joinAll([testSuiteFolderV4.path, 'optional']));
  final allDraft6 = testSuiteFolderV6.listSync()..addAll(optionalsV6.listSync());

  final runAllTestsForDraftX =
      (String schemaVersion, List<FileSystemEntity> allTests, List<String> skipFiles, List<String> skipTests) {
    String shortSchemaVersion = schemaVersion;
    if (schemaVersion == JsonSchemaVersions.draft4) {
      shortSchemaVersion = 'draft4';
    } else if (schemaVersion == JsonSchemaVersions.draft6) {
      shortSchemaVersion = 'draft6';
    }

    allTests.forEach((testEntry) {
      if (testEntry is File) {
        group('Validations ($shortSchemaVersion) ${path.basename(testEntry.path)}', () {
          // Skip these for now - reason shown
          if (skipFiles.contains(path.basename(testEntry.path))) return;

          final List tests = convert.JSON.decode((testEntry).readAsStringSync());
          tests.forEach((testEntry) {
            final schemaData = testEntry['schema'];
            final description = testEntry['description'];
            final List validationTests = testEntry['tests'];

            validationTests.forEach((validationTest) {
              final String validationDescription = validationTest['description'];
              final String testName = '${description} : ${validationDescription}';

              // Individual test cases to skip - reason listed in comments
              if (skipTests.contains(testName)) return;

              test(testName, () {
                final instance = validationTest['data'];
                bool validationResult;
                final bool expectedResult = validationTest['valid'];
                final checkResult = expectAsync0(() => expect(validationResult, expectedResult));
                JsonSchema.createSchema(schemaData, schemaVersion: schemaVersion).then((schema) {
                  validationResult = schema.validate(instance);
                  checkResult();
                });
              });
            });
          });
        });
      }
    });
  };

  final List<String> commonSkippedFiles = const [
    'refRemote.json', // We don't support this yet. Many libs don't
  ];

  final List<String> commonSkippedTests = const [
    'Recursive references between schemas : valid tree', // We don't yet support recursive refs.
    'Recursive references between schemas : invalid tree' // We don't yet support recursive refs.
  ];

  runAllTestsForDraftX(JsonSchemaVersions.draft4, allDraft4, commonSkippedFiles, commonSkippedTests);
  runAllTestsForDraftX(JsonSchemaVersions.draft6, allDraft6, commonSkippedFiles, commonSkippedTests);

  group('Schema self validation', () {
    for (final version in JsonSchemaVersions.allVersions) {
      test('version: $version', () {
        // Pull in the official schema, verify description and then ensure
        // that the schema satisfies the schema for schemas
        final url = version;
        JsonSchema.createSchemaFromUrl(url).then((schema) {
          expect(schema.schemaMap['description'], 'Core schema meta-schema');
          expect(schema.validate(schema.schemaMap), true);
        });
      });
    }
  });

  group('Nested \$refs: in root schema ', () {
    test('properties', () async {
      final barSchema = await JsonSchema.createSchema({
        "properties": {
          "foo": {"\$ref": "http://localhost:1234/integer.json#"},
          "bar": {"\$ref": "http://localhost:4321/string.json#"}
        },
        "required": ["foo", "bar"]
      });

      final isValid = barSchema.validate({"foo": 2, "bar": "test"});

      final isInvalid = barSchema.validate({"foo": 2, "bar": 4});

      expect(isValid, isTrue);
      expect(isInvalid, isFalse);
    });

    test('items', () async {
      final schema = await JsonSchema.createSchema({
        "items": {"\$ref": "http://localhost:1234/integer.json"}
      });

      final isValid = schema.validate([1, 2, 3, 4]);
      final isInvalid = schema.validate([1, 2, 3, '4']);

      expect(isValid, isTrue);
      expect(isInvalid, isFalse);
    });

    test('not / anyOf', () async {
      final schema = await JsonSchema.createSchema({
        "items": {
          "not": {
            "anyOf": [
              {"\$ref": "http://localhost:1234/integer.json#"},
              {"\$ref": "http://localhost:4321/string.json#"},
            ]
          }
        }
      });

      final isValid = schema.validate([3.4]);
      final isInvalid = schema.validate(['test']);

      expect(isValid, isTrue);
      expect(isInvalid, isFalse);
    });
  });
}
