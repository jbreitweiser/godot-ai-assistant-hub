@tool
class_name AIAssistantHub
extends Control

signal models_refreshed(models:Array[String])
signal new_api_loaded()

const NEW_AI_ASSISTANT_BUTTON = preload("res://addons/ai_assistant_hub/new_ai_assistant_button.tscn")
const NEW_AI_ASSISTANT_PATH = "res://addons/ai_assistant_hub/assistants/"

@onready var models_http_request: HTTPRequest = %ModelsHTTPRequest
@onready var url_txt: LineEdit = %UrlTxt
@onready var api_class_txt: LineEdit = %ApiClassTxt
@onready var models_list: ItemList = %ModelsList
@onready var no_assistants_guide: Label = %NoAssistantsGuide
@onready var assistant_types_container: HFlowContainer = %AssistantTypesContainer
@onready var tab_container: TabContainer = %TabContainer
@onready var llm_provider_option: OptionButton = %LLMProviderOption
@onready var url_label: Label = %UrlLabel
@onready var openrouter_key_container: HBoxContainer = %OpenRouterKeyContainer
@onready var openrouter_api_key: LineEdit = %OpenRouterAPIKey
@onready var api_load_btn: Button = %APILoadBtn
@onready var advanced_settings: HBoxContainer = %AdvancedSettings
@onready var assistants: HBoxContainer = %Assistants
@onready var assistants_refresh_btn: Button = %AssistantsRefreshBtn
@onready var assistants_new_btn: Button = %AssistantsNewBtn

var _plugin:EditorPlugin
var _tab_bar:TabBar
var _model_names:Array[String] = []
var _models_llm: LLMInterface
var _current_provider_id: String = ""


func _tab_changed(tab_index: int) -> void:
	if tab_index > 0:
		_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	else:
		_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER


func _close_tab(tab_index: int) -> void:
	var chat = tab_container.get_tab_control(tab_index)
	models_refreshed.disconnect(chat.refresh_models)
	chat.queue_free()


func initialize(plugin:EditorPlugin) -> void:
	_plugin = plugin
	_models_llm = _plugin.new_llm_provider()
	
	await ready
	url_txt.text = ProjectSettings.get_setting(AIHubPlugin.CONFIG_BASE_URL)
	api_class_txt.text = ProjectSettings.get_setting(AIHubPlugin.CONFIG_LLM_API)
	_current_provider_id = api_class_txt.text
	
	# Load OpenRouter API key
	if _current_provider_id == "openrouter_api":
		_load_openrouter_api_key()
	elif ProjectSettings.has_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY):
		openrouter_api_key.text = ProjectSettings.get_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY)
	
	# Initialize LLM provider dropdown
	_initialize_llm_provider_options()
	
	_on_assistants_refresh_btn_pressed()
	_on_refresh_models_btn_pressed()
	
	_tab_bar = tab_container.get_tab_bar()
	_tab_bar.tab_changed.connect(_tab_changed)
	_tab_bar.tab_close_pressed.connect(_close_tab)
	resize_refresh_btns()


func resize_refresh_btns() -> void:
	var btn_size = advanced_settings.size.y
	if api_load_btn:
		api_load_btn.custom_minimum_size.x = btn_size
	if assistants_refresh_btn:
		assistants_refresh_btn.custom_minimum_size.x = btn_size
	if assistants_new_btn:
		assistants_new_btn.custom_minimum_size.x = btn_size

# Initialize LLM provider options
func _initialize_llm_provider_options() -> void:
	llm_provider_option.clear()
	var providers = _plugin.get_available_llm_providers()
	
	for i in range(providers.size()):
		var provider = providers[i]
		llm_provider_option.add_item(provider.name)
		llm_provider_option.set_item_metadata(i, provider.id)
		
		# Select currently used provider
		if provider.id == _current_provider_id:
			llm_provider_option.select(i)
	
	# Update UI state
	_update_provider_ui()


# Update UI based on current provider selection
func _update_provider_ui() -> void:
	var provider_id = _current_provider_id
	
	# Ollama needs URL, OpenRouter needs API key
	if provider_id == "ollama_api":
		url_label.text = "Server URL"
		url_txt.placeholder_text = "Example: http://127.0.0.1:11434"
		url_txt.tooltip_text = "URL of the host running the LLM.\n\nDefault value uses Ollama's default port."
		url_txt.visible = true
		openrouter_key_container.visible = false
	elif provider_id == "openrouter_api":
		url_label.text = "OpenRouter Settings"
		url_txt.visible = false
		openrouter_key_container.visible = true
	else:
		url_label.text = "Server URL"
		url_txt.visible = true
		openrouter_key_container.visible = false


func _on_settings_changed(_x) -> void:
	ProjectSettings.set_setting(AIHubPlugin.CONFIG_BASE_URL, url_txt.text)
	ProjectSettings.set_setting(AIHubPlugin.CONFIG_LLM_API, api_class_txt.text)
	
	# Save OpenRouter API key
	if _current_provider_id == "openrouter_api":
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY, openrouter_api_key.text)
	ProjectSettings.save()


func _on_refresh_models_btn_pressed() -> void:
	models_list.clear()
	_models_llm.send_get_models_request(models_http_request)


func _on_models_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == 0:
		var models_returned: Array = _models_llm.read_models_response(body)
		if models_returned.size() == 0:
			models_list.add_item("No models found. Download at least one model and try again.")
		else:
			if models_returned[0] == LLMInterface.INVALID_RESPONSE:
				models_list.add_item("Error while trying to get the models list. Response: %s" % _models_llm.get_full_response(body))
			else:
				_model_names = models_returned
				for model in _model_names:
					models_list.add_item(model)
				models_refreshed.emit(_model_names) #for existing chats
	else:
		push_error("HTTP response: Result: %s, Response Code: %d, Headers: %s, Body: %s" % [result, response_code, headers, body])
		models_list.add_item("Something went wrong querying for models, is the Server URL correct?")


func _on_assistants_refresh_btn_pressed() -> void:
	var assistants_path = "%s/assistants" % self.scene_file_path.get_base_dir()
	var files = _get_all_resources(assistants_path)
	var found:= false
	
	for child in assistant_types_container.get_children():
		if child != no_assistants_guide:
			assistant_types_container.remove_child(child)
	
	for assistant_file in files:
		var assistant = load(assistant_file)
		if assistant is AIAssistantResource:
			found = true
			var new_bot_btn:NewAIAssistantButton= NEW_AI_ASSISTANT_BUTTON.instantiate()
			new_bot_btn.initialize(_plugin, assistant)
			new_bot_btn.chat_created.connect(_on_new_bot_btn_chat_created)
			assistant_types_container.add_child(new_bot_btn)
	
	if not found:
		no_assistants_guide.text = "You have no assistant types! Create a new AIAssistantResource in the assistants folder, then click the refresh button. The folder is at: %s" % assistants_path
		no_assistants_guide.visible = true
		assistant_types_container.visible = false
	else:
		no_assistants_guide.visible = false
		assistant_types_container.visible = true


func _on_new_bot_btn_chat_created(chat:AIChat, assistant_type:AIAssistantResource) -> void:
	tab_container.add_child(chat)
	tab_container.set_tab_icon(tab_container.get_child_count() - 1, assistant_type.type_icon)
	chat.refresh_models(_model_names)
	models_refreshed.connect(chat.refresh_models)
	new_api_loaded.connect(chat.load_api)
	chat.greet()


func _get_all_resources(path: String) -> Array[String]:  
	var file_paths: Array[String] = []  
	var dir = DirAccess.open(path)  
	dir.list_dir_begin()  
	var file_name = dir.get_next()  
	while not file_name.is_empty():  
		if file_name.ends_with(".tres"):
			var file_path = path + "/" + file_name
			file_paths.append(file_path)  
		file_name = dir.get_next()
	return file_paths


func _on_api_load_btn_pressed() -> void:
	var new_llm:LLMInterface = _plugin.new_llm_provider()
	if new_llm == null:
		push_error("Invalid API class")
		return
	_models_llm = new_llm
	new_api_loaded.emit()


# Called when LLM provider option changes
func _on_llm_provider_option_item_selected(index: int) -> void:
	var provider_id = llm_provider_option.get_item_metadata(index)
	if _current_provider_id != provider_id:
		_current_provider_id = provider_id
		api_class_txt.text = provider_id
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_LLM_API, provider_id)
		
		# Load API key for OpenRouter if we're switching to it
		if provider_id == "openrouter_api":
			_load_openrouter_api_key()
			
		_update_provider_ui()
		_on_api_load_btn_pressed()


# Load OpenRouter API key from the API class
func _load_openrouter_api_key() -> void:
	var openrouter_api = load("res://addons/ai_assistant_hub/llm_apis/openrouter_api.gd").new()
	var api_key = openrouter_api._get_api_key()
	if not api_key.is_empty():
		openrouter_api_key.text = api_key


# Called when OpenRouter API key changes
func _on_openrouter_api_key_text_changed(new_text: String) -> void:
	# Save to ProjectSettings for backward compatibility
	ProjectSettings.set_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY, new_text)
	
	# Save to file using the OpenRouter API class
	if _current_provider_id == "openrouter_api":
		var openrouter_api = load("res://addons/ai_assistant_hub/llm_apis/openrouter_api.gd").new()
		openrouter_api.save_api_key(new_text)
	ProjectSettings.save()


func _on_assistants_new_btn_pressed() -> void:
	var provider_name = llm_provider_option.get_item_text(llm_provider_option.selected) + ".tres"
	var dialog_text = "Provide an assistant name.  This will be the file name as well as the button text."
	show_file_dialog("AI Assistant Filename", provider_name, NEW_AI_ASSISTANT_PATH, dialog_text, file_selected)

func show_file_dialog(title: String, filename: String, start_dir: String, dialog_text: String, call_back: Callable):
	# Create file dialog
	var dialog = EditorFileDialog.new()
	add_child(dialog)
	dialog.title = title
	dialog.dialog_text = dialog_text
	dialog.current_dir = start_dir
	dialog.current_file = filename
	dialog.file_selected.connect(call_back)
	dialog.popup_file_dialog()


func file_selected(filename: String): 
	var selected_model: String
	var selected_indices = models_list.get_selected_items()
	for i in selected_indices:
		selected_model = models_list.get_item_text(i)

	if selected_model.is_empty():
		popup_confirm("Model is not selected.  Highlight a model name")
		return
		
	var provider_name = llm_provider_option.get_item_text(llm_provider_option.selected) # Assuming llm_provider is a Label or similar
	var new_assistant_resource = AIAssistantResource.new()
	
	if filename.is_empty():
		filename = _get_next_file_name(NEW_AI_ASSISTANT_PATH, "tres" , provider_name)
	
	new_assistant_resource.resource_path = filename
	 
	new_assistant_resource.ai_model = selected_model
	new_assistant_resource.type_name = provider_name
	new_assistant_resource.api_class = api_class_txt.text

	ResourceSaver.save(new_assistant_resource)
	EditorInterface.edit_resource(new_assistant_resource)
	
	_on_assistants_refresh_btn_pressed()

func _get_next_file_name(path: String, ext: String, filename: String, num: int = 0) -> String:
	var new_filename
	
	if(num == 0):
		new_filename = "%s/%s.%s" % [path, filename, ext]
	else:
		new_filename = "%s/%s(%s).%s" % [path, filename,num, ext]
	
	if ResourceLoader.exists(new_filename):
		return _get_next_file_name(path, ext, filename, num+1)
	else:
		return new_filename
	
func popup_confirm(message: String) -> void:
	var dialog:AcceptDialog = AcceptDialog.new()
	add_child(dialog)
	dialog.dialog_text = message
	dialog.popup_centered()
