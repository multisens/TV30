#!/bin/bash

TOPIC="sensor/comprehensive/test"
CLIENT="test-client"

echo "=== TESTE 1: Mensagem válida completa ==="
docker exec mosquitto-plugin mosquitto_pub -t "$TOPIC" -m '{
  "string_field": "hello",
  "number_field": 50,
  "integer_field": 25,
  "boolean_field": true,
  "enum_field": "option2",
  "const_field": "fixed_value",
  "array_field": [1, 2, 3],
  "nested_object": {
    "nested_string": "test",
    "nested_number": 5
  }
}' -i "$CLIENT"
echo "Status: $?"
echo ""

echo "=== TESTE 2: string_field - minLength violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"ab\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 3: string_field - maxLength violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"verylongstringthatexceedslimit\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 4: string_field - pattern violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"Hello123\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 5: number_field - minimum violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 5, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 6: number_field - maximum violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 150, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 7: number_field - multipleOf violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 47, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 8: integer_field - exclusiveMinimum violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 0, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 9: integer_field - exclusiveMaximum violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 50, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 10: boolean_field - type violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": \"not_a_bool\", \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 11: enum_field - invalid value ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"invalid_option\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 12: const_field - wrong value ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"wrong_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 13: array_field - minItems violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\", \"array_field\": [1]}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 14: array_field - maxItems violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\", \"array_field\": [1,2,3,4,5,6]}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 15: array_field - uniqueItems violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\", \"array_field\": [1,2,2,3]}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 16: array_field - item validation (value > 10) ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\", \"array_field\": [1,2,15]}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 17: required field missing ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 18: additionalProperties violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\", \"extra_field\": \"not_allowed\"}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 19: nested_object - missing required field ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\", \"nested_object\": {\"nested_number\": 5}}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== TESTE 20: nested_object - maxProperties violation ==="
docker exec mosquitto-plugin sh -c 'mosquitto_sub -t "errors/validation" -C 1 -W 2 & SUB_PID=$!; sleep 0.5; mosquitto_pub -t "'"$TOPIC"'" -m "{\"string_field\": \"hello\", \"number_field\": 50, \"integer_field\": 25, \"boolean_field\": true, \"enum_field\": \"option1\", \"const_field\": \"fixed_value\", \"nested_object\": {\"nested_string\": \"test\", \"nested_number\": 5, \"extra\": \"field\"}}" -i "'"$CLIENT"'"; wait $SUB_PID'
echo ""

echo "=== Testes concluídos ==="
