@tool
class_name JanAPI
extends LLMInterface

const HEADERS := ["Content-Type: application/json"]

func send_get_models_request(http_request: HTTPRequest) -> bool:
	var base := ProjectSettings.get_setting(AIHubPlugin.CONFIG_BASE_URL)
	var url := "%s/v1/models" % base
	var err := http_request.request(url, HEADERS, HTTPClient.METHOD_GET)
	if err != OK:
		push_error("JanAPI GET models failed: %s" % url)
		return false
	return true

func read_models_response(body: PackedByteArray) -> Array[String]:
	var j := JSON.new()
	j.parse(body.get_string_from_utf8())
	var data := j.get_data()
	if data.has("data") and data.data is Array:
		var out := []
		for m in data.data:
			if m.has("id"):
				out.append(m.id)
		out.sort()
		return out
	return [INVALID_RESPONSE]

func send_chat_request(http_request: HTTPRequest, content: Array) -> bool:
	if model.is_empty():
		push_error("JanAPI: no model set!")
		return false
	var body := {
		"model": model,
		"messages": content
	}
	if override_temperature:
		body["temperature"] = temperature
	var payload := JSON.new().stringify(body)
	var base := ProjectSettings.get_setting(AIHubPlugin.CONFIG_BASE_URL)
	var url := "%s/v1/chat/completions" % base
	var err := http_request.request(url, HEADERS, HTTPClient.METHOD_POST, payload)
	if err != OK:
		push_error("JanAPI chat request failed: %s\n%s" % [url, payload])
		return false
	return true

func read_response(body: PackedByteArray) -> String:
	var j := JSON.new()
	j.parse(body.get_string_from_utf8())
	var data := j.get_data()
	if data.has("choices") and data.choices.size() > 0:
		var c = data.choices[0]
		if c.has("message") and c.message.has("content"):
			return ResponseCleaner.clean(c.message.content)
	return INVALID_RESPONSE
 
