namespace Slack\Hack\JsonSchema\Codegen;

use namespace HH\Lib\{C, Vec};

final class SchemaPreprocessor {

  /**
   * Apply preprocessing to handle propertyNames with $ref to enums.
   */
  public static function preprocessSchemaForEnumKeys(TSchema $schema, string $schema_file_path): TSchema {
    $schema_dict = Shapes::toDict($schema);
    $preprocessed = self::preprocessSchemaForEnumKeysRecursive($schema_dict, $schema_file_path);
    return type_assert_shape($preprocessed, 'Slack\Hack\JsonSchema\Codegen\TSchema');
  }

  private static function preprocessSchemaForEnumKeysRecursive(
    dict<arraykey, mixed> $schema,
    string $schema_file_path,
  ): dict<arraykey, mixed> {
    // Recursively process the schema
    $processed_schema = dict[];
    foreach ($schema as $key => $value) {
      if ($key === 'properties' && $value is dict<_, _>) {
        // Recursively process properties
        $processed_properties = dict[];
        foreach ($value as $prop_key => $prop_value) {
          if ($prop_value is dict<_, _>) {
            $prop_value_dict = $prop_value as dict<_, _>;
            $processed_properties[$prop_key] =
              self::preprocessSchemaForEnumKeysRecursive($prop_value_dict, $schema_file_path);
          } else {
            $processed_properties[$prop_key] = $prop_value;
          }
        }
        $processed_schema[$key] = $processed_properties;
      } else if ($value is dict<_, _>) {
        $value_dict = $value as dict<_, _>;
        $processed_schema[$key] = self::preprocessSchemaForEnumKeysRecursive($value_dict, $schema_file_path);
      } else if ($value is vec<_>) {
        // Process arrays recursively
        $processed_array = vec[];
        foreach ($value as $item) {
          if ($item is dict<_, _>) {
            $item_dict = $item as dict<_, _>;
            $processed_array[] = self::preprocessSchemaForEnumKeysRecursive($item_dict, $schema_file_path);
          } else {
            $processed_array[] = $item;
          }
        }
        $processed_schema[$key] = $processed_array;
      } else {
        $processed_schema[$key] = $value;
      }
    }

    // Check if this schema has propertyNames with $ref pattern that needs expansion
    if (C\contains_key($processed_schema, 'propertyNames')) {
      $property_names = $processed_schema['propertyNames'];
      if ($property_names is dict<_, _> && C\contains_key($property_names, '$ref')) {
        $property_names_dict = $property_names as dict<_, _>;
        $ref_path = $property_names_dict['$ref'] as string;

        // Resolve the $ref to get the enum values
        $enum_values = self::resolveEnumRef($ref_path, $schema_file_path);
        if ($enum_values is nonnull) {
          // Convert to explicit properties instead of propertyNames
          $properties = dict[];

          // Use additionalProperties schema if present, otherwise allow mixed values
          $value_schema = C\contains_key($processed_schema, 'additionalProperties')
            ? $processed_schema['additionalProperties']
            : dict[]; // Empty schema allows any type (mixed)

          foreach ($enum_values as $enum_value) {
            $properties[$enum_value] = $value_schema;
          }

          // Replace the schema structure
          $processed_schema['properties'] = $properties;
          $processed_schema['additionalProperties'] = false;
          unset($processed_schema['propertyNames']);
        }
      }
    }

    return $processed_schema;
  }

  private static function resolveEnumRef(string $ref_path, string $schema_file_path): ?vec<string> {
    // Convert relative path to absolute path
    $schema_dir = \dirname($schema_file_path);
    $full_path = $schema_dir.'/'.$ref_path;

    // Normalize the path (resolve .. and . components)
    $full_path = \realpath($full_path) ?: $full_path;

    if (!\file_exists($full_path)) {
      return null;
    }

    $contents = \file_get_contents($full_path);
    if (!$contents) {
      return null;
    }

    $enum_schema = \json_decode($contents, true, 512, \JSON_FB_HACK_ARRAYS);
    if ($enum_schema === null) {
      throw new \Exception("Failed decoding enum schema: `{$full_path}`");
    }

    if (
      $enum_schema is dict<_, _> && ($enum_schema['type'] ?? null) === 'string' && C\contains_key($enum_schema, 'enum')
    ) {
      $enum_array = $enum_schema['enum'];
      if ($enum_array is vec<_>) {
        $enum_values = vec[];
        foreach ($enum_array as $value) {
          if ($value is string) {
            $enum_values[] = $value;
          }
        }
        return $enum_values;
      }
    }

    return null;
  }
}
