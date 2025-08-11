namespace Slack\Hack\JsonSchema\Tests;

use function Facebook\FBExpect\expect;
use namespace HH\Lib\C;
use namespace Slack\Hack\JsonSchema;

use type Slack\Hack\JsonSchema\Tests\Generated\{
  PropertyNamesRefSchemaValidator,
  PropertyNamesNestedSchemaValidator,
  PropertyNamesNoAdditionalPropsSchemaValidator,
};

final class PropertyNamesRefSchemaValidatorTest extends BaseCodegenTestCase {

  <<__Override>>
  public static async function beforeFirstTestAsync(): Awaitable<void> {
    // Generate validator for basic propertyNames with $ref scenario
    $ret1 = self::getBuilder(
      'property-names-ref-schema.json',
      'PropertyNamesRefSchemaValidator',
      shape(
        'refs' => shape(
          'unique' => shape(
            'source_root' => __DIR__,
            'output_root' => __DIR__.'/examples/codegen',
          ),
        ),
      ),
    );
    $ret1['codegen']->build();
    require_once($ret1['path']);

    // Generate validator for nested propertyNames with $ref scenario
    $ret2 = self::getBuilder(
      'property-names-nested-schema.json',
      'PropertyNamesNestedSchemaValidator',
      shape(
        'refs' => shape(
          'unique' => shape(
            'source_root' => __DIR__,
            'output_root' => __DIR__.'/examples/codegen',
          ),
        ),
      ),
    );
    $ret2['codegen']->build();
    require_once($ret2['path']);

    // Generate validator for propertyNames without additionalProperties
    $ret3 = self::getBuilder(
      'property-names-no-additional-props-schema.json',
      'PropertyNamesNoAdditionalPropsSchemaValidator',
      shape(
        'refs' => shape(
          'unique' => shape(
            'source_root' => __DIR__,
            'output_root' => __DIR__.'/examples/codegen',
          ),
        ),
      ),
    );
    $ret3['codegen']->build();
    require_once($ret3['path']);
  }

  public function testBasicPropertyNamesRefTransformation(): void {
    $cases = vec[
      // Valid cases - should accept objects with only the enum keys
      shape(
        'input' => dict['foo' => 'value1'],
        'output' => shape('foo' => 'value1'),
        'valid' => true,
      ),
      shape(
        'input' => dict['bar' => 'value2'],
        'output' => shape('bar' => 'value2'),
        'valid' => true,
      ),
      shape(
        'input' => dict['baz' => 'value3'],
        'output' => shape('baz' => 'value3'),
        'valid' => true,
      ),
      shape(
        'input' => dict['foo' => 'value1', 'bar' => 'value2'],
        'output' => shape('foo' => 'value1', 'bar' => 'value2'),
        'valid' => true,
      ),
      shape(
        'input' => dict['foo' => 'value1', 'bar' => 'value2', 'baz' => 'value3'],
        'output' => shape('foo' => 'value1', 'bar' => 'value2', 'baz' => 'value3'),
        'valid' => true,
      ),
      // Empty object should be valid
      shape(
        'input' => dict[],
        'output' => shape(),
        'valid' => true,
      ),
      // Invalid cases - should reject objects with keys not in the enum
      shape(
        'input' => dict['invalid' => 'value'],
        'valid' => false,
      ),
      shape(
        'input' => dict['foo' => 'value1', 'invalid' => 'value2'],
        'valid' => false,
      ),
      // Invalid cases - should reject non-string values
      shape(
        'input' => dict['foo' => 123],
        'valid' => false,
      ),
      shape(
        'input' => dict['bar' => null],
        'valid' => false,
      ),
      // Invalid case - not an object
      shape(
        'input' => 'not an object',
        'valid' => false,
      ),
    ];

    $this->expectCases($cases, $input ==> new PropertyNamesRefSchemaValidator($input));
  }

  public function testNestedPropertyNamesRefTransformation(): void {
    $cases = vec[
      // Valid nested structure
      shape(
        'input' => dict[
          'metadata' => dict['foo' => 1, 'bar' => 2],
          'data' => dict['one' => true, 'two' => false],
        ],
        'output' => shape(
          'metadata' => shape('foo' => 1, 'bar' => 2),
          'data' => shape('one' => true, 'two' => false),
        ),
        'valid' => true,
      ),
      // Valid with partial properties
      shape(
        'input' => dict[
          'metadata' => dict['baz' => 42],
        ],
        'output' => shape(
          'metadata' => shape('baz' => 42),
        ),
        'valid' => true,
      ),
      // Invalid metadata key
      shape(
        'input' => dict[
          'metadata' => dict['invalid_key' => 1],
        ],
        'valid' => false,
      ),
      // Invalid data key
      shape(
        'input' => dict[
          'data' => dict['invalid_number' => true],
        ],
        'valid' => false,
      ),
      // Invalid metadata value type (should be number)
      shape(
        'input' => dict[
          'metadata' => dict['foo' => 'not_a_number'],
        ],
        'valid' => false,
      ),
      // Invalid data value type (should be boolean)
      shape(
        'input' => dict[
          'data' => dict['one' => 'not_a_boolean'],
        ],
        'valid' => false,
      ),
    ];

    $this->expectCases($cases, $input ==> new PropertyNamesNestedSchemaValidator($input));
  }

  public function testPropertyNamesWithoutAdditionalProperties(): void {
    // This schema only has propertyNames but no additionalProperties
    // The preprocessing should still transform it, creating properties with mixed values
    $cases = vec[
      // Valid enum keys with various value types should all work (mixed)
      shape(
        'input' => dict['foo' => 'string_value'],
        'output' => shape('foo' => 'string_value'),
        'valid' => true,
      ),
      shape(
        'input' => dict['bar' => 123],
        'output' => shape('bar' => 123),
        'valid' => true,
      ),
      shape(
        'input' => dict['baz' => true],
        'output' => shape('baz' => true),
        'valid' => true,
      ),
      shape(
        'input' => dict['foo' => null],
        'output' => shape('foo' => null),
        'valid' => true,
      ),
      // Invalid keys should still be rejected
      shape(
        'input' => dict['invalid_key' => 'value'],
        'valid' => false,
      ),
      // Mixed valid and invalid keys
      shape(
        'input' => dict['foo' => 'valid', 'invalid' => 'should_fail'],
        'valid' => false,
      ),
    ];

    $this->expectCases($cases, $input ==> new PropertyNamesNoAdditionalPropsSchemaValidator($input));
  }

  public function testEnumPropertyKeysAreStrictlyEnforced(): void {
    // Test that demonstrates the key benefit: only enum keys are allowed
    $validator = new PropertyNamesRefSchemaValidator(dict[
      'foo' => 'valid',
      'completely_invalid_key' => 'should_fail',
    ]);

    $validator->validate();
    expect($validator->isValid())->toBeFalse();

    $errors = $validator->getErrors();
    expect(C\count($errors))->toBeGreaterThan(0);

    // Verify the error mentions the invalid additional property
    $error_messages = \HH\Lib\Vec\map($errors, $error ==> $error['message'] ?? '');
    $has_additional_property_error =
      \HH\Lib\Vec\filter($error_messages, $msg ==> \HH\Lib\Str\contains($msg, 'additional property'));
    expect(C\count($has_additional_property_error))->toBeGreaterThan(0);
  }

  public function testGeneratedTypeIsCorrect(): void {
    // Test that the generated validator produces the correct typed output
    $validator = new PropertyNamesRefSchemaValidator(dict[
      'foo' => 'test1',
      'bar' => 'test2',
    ]);

    $validator->validate();
    expect($validator->isValid())->toBeTrue();

    $validated = $validator->getValidatedInput();

    // The output should be a proper shape, not a generic dict
    expect($validated['foo'] ?? null)->toBeSame('test1');
    expect($validated['bar'] ?? null)->toBeSame('test2');
    expect(\HH\Lib\C\contains_key($validated, 'baz'))->toBeFalse();
  }

}
