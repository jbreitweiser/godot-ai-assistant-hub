@tool
class_name OpenRouterAPI
extends LLMInterface

# OpenRouter API basic configuration
const API_KEY_SETTING := "plugins/ai_assistant_hub/openrouter_api_key"
const BASE_URL := "https://openrouter.ai/api/v1"
const DEFAULT_MODEL := ""
const API_KEY_FILE := "res://addons/ai_assistant_hub/llm_apis/openrouter_api_key.gd"

# HTTP headers required for every request
var _headers := PackedStringArray([
	"Content-Type: application/json",
	"Authorization: Bearer {api_key}",  # Will be dynamically replaced before the request
	"HTTP-Referer: godot://ai_assistant_hub", # OpenRouter requires source reference
])

# Get model list
func send_get_models_request(http_request: HTTPRequest) -> bool:
	var api_key := _get_api_key()
	if api_key.is_empty():
		push_error("OpenRouter API key not set. Please configure the API key in project settings.")
		return false
	
	var headers := _get_headers_with_api_key(api_key)
	var url := "%s/models" % BASE_URL
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("OpenRouter API request failed: %s" % url)
		return false
	return true

# Parse model list response
func read_models_response(body: PackedByteArray) -> Array[String]:
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var response := json.get_data()
	
	if response.has("data") and response.data is Array:
		var model_names: Array[String] = []
		for model in response.data:
			if model.has("id"):
				model_names.append(model.id)
		model_names.sort()
		return model_names
	else:
		push_error("Failed to get model list from OpenRouter: %s" % JSON.stringify(response))
		return [INVALID_RESPONSE]

# Send chat request
func send_chat_request(http_request: HTTPRequest, content: Array) -> bool:
	var api_key := _get_api_key()
	if api_key.is_empty():
		push_error("OpenRouter API key not set. Please configure the API key in project settings.")
		return false
	
	# Ensure model is set
	if model.is_empty():
		model = DEFAULT_MODEL
		push_warning("Model not set, using default model: %s" % model)
	
	# Build request body
	var body_dict := {
		"model": model,
		"messages": content
	}
	
	# Add temperature setting (if needed)
	if override_temperature:
		body_dict["temperature"] = temperature
	
	var body := JSON.stringify(body_dict)
	var headers := _get_headers_with_api_key(api_key)
	var url := "%s/chat/completions" % BASE_URL
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error("OpenRouter API chat request failed.\nURL: %s\nRequest body: %s" % [url, body])
		return false
	return true

# Parse chat response
func read_response(body: PackedByteArray) -> String:
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var response := json.get_data()
	
	if response.has("choices") and response.choices.size() > 0:
		if response.choices[0].has("message") and response.choices[0].message.has("content"):
			return ResponseCleaner.clean(response.choices[0].message.content)
	
	push_error("Failed to parse OpenRouter response: %s" % JSON.stringify(response))
	return INVALID_RESPONSE

# Helper method: Get API key - tries to load from file first, then falls back to ProjectSettings
func _get_api_key() -> String:
	# First try to load from file
	var api_key := _load_api_key_from_file()
	
	# If not found in file, try ProjectSettings
	if api_key.is_empty() and ProjectSettings.has_setting(API_KEY_SETTING):
		api_key = ProjectSettings.get_setting(API_KEY_SETTING)
		# If we found a key in ProjectSettings, save it to file for next time
		if not api_key.is_empty():
			_save_api_key_to_file(api_key)
	
	return api_key

# Save API key to file
func _save_api_key_to_file(api_key: String) -> void:
	var file_content := """@tool
extends Resource

# This file is auto-generated. Do not edit manually.
# It stores the OpenRouter API key for the AI Assistant Hub plugin.

const API_KEY := "%s"
"""
	file_content = file_content % api_key
	
	var file := FileAccess.open(API_KEY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(file_content)
		file.close()
	else:
		push_error("Failed to save OpenRouter API key to file: %s" % API_KEY_FILE)

# Load API key from file
func _load_api_key_from_file() -> String:
	if not FileAccess.file_exists(API_KEY_FILE):
		return ""
		
	var file := FileAccess.open(API_KEY_FILE, FileAccess.READ)
	if not file:
		push_error("Failed to open OpenRouter API key file: %s" % API_KEY_FILE)
		return ""
		
	var content := file.get_as_text()
	file.close()
	
	var regex := RegEx.new()
	regex.compile('const API_KEY := "([^"]*)"')
	var result := regex.search(content)
	
	if result and result.get_group_count() > 0:
		return result.get_string(1)
	
	return ""

# Helper method: Get request headers with API key
func _get_headers_with_api_key(api_key: String) -> PackedStringArray:
	var headers := []
	for header in _headers:
		if header.begins_with("Authorization:"):
			headers.append("Authorization: Bearer %s" % api_key)
		else:
			headers.append(header)
	return PackedStringArray(headers)

# Public method to save API key - called when user changes the key in UI
func save_api_key(api_key: String) -> void:
	_save_api_key_to_file(api_key)
	# Also update ProjectSettings for backward compatibility
	ProjectSettings.set_setting(API_KEY_SETTING, api_key) 
