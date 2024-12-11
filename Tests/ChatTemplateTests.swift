//
//  ChatTemplateTests.swift
//
//
//  Created by John Mai on 2024/3/24.
//

import XCTest

@testable import Jinja

let llama3_2visionChatTemplate = "{{- bos_token }}\n{%- if custom_tools is defined %}\n    {%- set tools = custom_tools %}\n{%- endif %}\n{%- if not tools_in_user_message is defined %}\n    {%- set tools_in_user_message = true %}\n{%- endif %}\n{%- if not date_string is defined %}\n    {%- if strftime_now is defined %}\n        {%- set date_string = strftime_now(\"%d %b %Y\") %}\n    {%- else %}\n        {%- set date_string = \"26 Jul 2024\" %}\n    {%- endif %}\n{%- endif %}\n{%- if not tools is defined %}\n    {%- set tools = none %}\n{%- endif %}\n\n{#- This block extracts the system message, so we can slot it into the right place. #}\n{%- if messages[0]['role'] == 'system' %}\n    {%- set system_message = messages[0]['content']|trim %}\n    {%- set messages = messages[1:] %}\n{%- else %}\n    {%- set system_message = \"\" %}\n{%- endif %}\n\n{#- Find out if there are any images #}\n{% set image_ns = namespace(has_images=false) %}      \n{%- for message in messages %}\n    {%- for content in message['content'] %}\n        {%- if content['type'] == 'image' %}\n            {%- set image_ns.has_images = true %}\n        {%- endif %}\n    {%- endfor %}\n{%- endfor %}\n\n{#- Error out if there are images and system message #}\n{%- if image_ns.has_images and not system_message == \"\" %}\n    {{- raise_exception(\"Prompting with images is incompatible with system messages.\") }}\n{%- endif %}\n\n{#- System message if there are no images #}\n{%- if not image_ns.has_images %}\n    {{- \"<|start_header_id|>system<|end_header_id|>\\n\\n\" }}\n    {%- if tools is not none %}\n        {{- \"Environment: ipython\\n\" }}\n    {%- endif %}\n    {{- \"Cutting Knowledge Date: December 2023\\n\" }}\n    {{- \"Today Date: \" + date_string + \"\\n\\n\" }}\n    {%- if tools is not none and not tools_in_user_message %}\n        {{- \"You have access to the following functions. To call a function, please respond with JSON for a function call.\" }}\n        {{- 'Respond in the format {\"name\": function name, \"parameters\": dictionary of argument name and its value}.' }}\n        {{- \"Do not use variables.\\n\\n\" }}\n        {%- for t in tools %}\n            {{- t | tojson(indent=4) }}\n            {{- \"\\n\\n\" }}\n        {%- endfor %}\n    {%- endif %}\n    {{- system_message }}\n    {{- \"<|eot_id|>\" }}\n{%- endif %}\n\n{#- Custom tools are passed in a user message with some extra guidance #}\n{%- if tools_in_user_message and not tools is none %}\n    {#- Extract the first user message so we can plug it in here #}\n    {%- if messages | length != 0 %}\n        {%- set first_user_message = messages[0]['content']|trim %}\n        {%- set messages = messages[1:] %}\n    {%- else %}\n        {{- raise_exception(\"Cannot put tools in the first user message when there's no first user message!\") }}\n{%- endif %}\n    {{- '<|start_header_id|>user<|end_header_id|>\\n\\n' -}}\n    {{- \"Given the following functions, please respond with a JSON for a function call \" }}\n    {{- \"with its proper arguments that best answers the given prompt.\\n\\n\" }}\n    {{- 'Respond in the format {\"name\": function name, \"parameters\": dictionary of argument name and its value}.' }}\n    {{- \"Do not use variables.\\n\\n\" }}\n    {%- for t in tools %}\n        {{- t | tojson(indent=4) }}\n        {{- \"\\n\\n\" }}\n    {%- endfor %}\n    {{- first_user_message + \"<|eot_id|>\"}}\n{%- endif %}\n\n{%- for message in messages %}\n    {%- if not (message.role == 'ipython' or message.role == 'tool' or 'tool_calls' in message) %}\n    {{- '<|start_header_id|>' + message['role'] + '<|end_header_id|>\\n\\n' }}\n        {%- if message['content'] is string %}\n            {{- message['content'] }}\n        {%- else %}\n            {%- for content in message['content'] %}\n                {%- if content['type'] == 'image' %}\n                    {{- '<|image|>' }}\n                {%- elif content['type'] == 'text' %}\n                    {{- content['text'] }}\n                {%- endif %}\n            {%- endfor %}\n        {%- endif %}\n        {{- '<|eot_id|>' }}\n    {%- elif 'tool_calls' in message %}\n        {%- if not message.tool_calls|length == 1 %}\n            {{- raise_exception(\"This model only supports single tool-calls at once!\") }}\n        {%- endif %}\n        {%- set tool_call = message.tool_calls[0].function %}\n        {{- '<|start_header_id|>assistant<|end_header_id|>\\n\\n' -}}\n        {{- '{\"name\": \"' + tool_call.name + '\", ' }}\n        {{- '\"parameters\": ' }}\n        {{- tool_call.arguments | tojson }}\n        {{- \"}\" }}\n        {{- \"<|eot_id|>\" }}\n    {%- elif message.role == \"tool\" or message.role == \"ipython\" %}\n        {{- \"<|start_header_id|>ipython<|end_header_id|>\\n\\n\" }}\n        {%- if message.content is mapping or message.content is iterable %}\n            {{- message.content | tojson }}\n        {%- else %}\n            {{- message.content }}\n        {%- endif %}\n        {{- \"<|eot_id|>\" }}\n    {%- endif %}\n{%- endfor %}\n{%- if add_generation_prompt %}\n    {{- '<|start_header_id|>assistant<|end_header_id|>\\n\\n' }}\n{%- endif %}\n"
let qwen2VLChatTemplate = "{% set image_count = namespace(value=0) %}{% set video_count = namespace(value=0) %}{% for message in messages %}{% if loop.first and message['role'] != 'system' %}<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n{% endif %}<|im_start|>{{ message['role'] }}\n{% if message['content'] is string %}{{ message['content'] }}<|im_end|>\n{% else %}{% for content in message['content'] %}{% if content['type'] == 'image' or 'image' in content or 'image_url' in content %}{% set image_count.value = image_count.value + 1 %}{% if add_vision_id %}Picture {{ image_count.value }}: {% endif %}<|vision_start|><|image_pad|><|vision_end|>{% elif content['type'] == 'video' or 'video' in content %}{% set video_count.value = video_count.value + 1 %}{% if add_vision_id %}Video {{ video_count.value }}: {% endif %}<|vision_start|><|video_pad|><|vision_end|>{% elif 'text' in content %}{{ content['text'] }}{% endif %}{% endfor %}<|im_end|>\n{% endif %}{% endfor %}{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}"

let messages: [[String: String]] = [
    [
        "role": "user",
        "content": "Hello, how are you?",
    ],
    [
        "role": "assistant",
        "content": "I'm doing great. How can I help you today?",
    ],
    [
        "role": "user",
        "content": "I'd like to show off how chat templating works!",
    ],
]

let messagesWithSystem: [[String: String]] =
    [
        [
            "role": "system",
            "content": "You are a friendly chatbot who always responds in the style of a pirate",
        ]
    ] + messages

final class ChatTemplateTests: XCTestCase {
    struct Test {
        let name: String
        let chatTemplate: String
        let data: [String: Any]
        let target: String
    }

    let defaultTemplates: [Test] = [
        Test(
            name: "Generic chat template with messages",
            chatTemplate:
                "{% for message in messages %}{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}{% endfor %}{% if add_generation_prompt %}{{ '<|im_start|>assistant\n' }}{% endif %}",
            data: [
                "messages": messages,
                "add_generation_prompt": false,
            ],
            target:
                "<|im_start|>user\nHello, how are you?<|im_end|>\n<|im_start|>assistant\nI'm doing great. How can I help you today?<|im_end|>\n<|im_start|>user\nI'd like to show off how chat templating works!<|im_end|>\n"
        ),
        // facebook/blenderbot-400M-distill
        Test(
            name: "facebook/blenderbot-400M-distill",
            chatTemplate:
                "{% for message in messages %}{% if message['role'] == 'user' %}{{ ' ' }}{% endif %}{{ message['content'] }}{% if not loop.last %}{{ '  ' }}{% endif %}{% endfor %}{{ eos_token }}",
            data: [
                "messages": messages,
                "eos_token": "</s>",
            ],
            target:
                " Hello, how are you?  I'm doing great. How can I help you today?   I'd like to show off how chat templating works!</s>"
        ),
        // facebook/blenderbot_small-90M
        Test(
            name: "facebook/blenderbot_small-90M",
            chatTemplate:
                "{% for message in messages %}{% if message['role'] == 'user' %}{{ ' ' }}{% endif %}{{ message['content'] }}{% if not loop.last %}{{ '  ' }}{% endif %}{% endfor %}{{ eos_token }}",
            data: [
                "messages": messages,
                "eos_token": "</s>",
            ],
            target:
                " Hello, how are you?  I'm doing great. How can I help you today?   I'd like to show off how chat templating works!</s>"
        ),
        // bigscience/bloom
        Test(
            name: "bigscience/bloom",
            chatTemplate: "{% for message in messages %}{{ message.content }}{{ eos_token }}{% endfor %}",
            data: [
                "messages": messages,
                "eos_token": "</s>",
            ],
            target:
                "Hello, how are you?</s>I'm doing great. How can I help you today?</s>I'd like to show off how chat templating works!</s>"
        ),
        // EleutherAI/gpt-neox-20b
        Test(
            name: "EleutherAI/gpt-neox-20b",
            chatTemplate: "{% for message in messages %}{{ message.content }}{{ eos_token }}{% endfor %}",
            data: [
                "messages": messages,
                "eos_token": "<|endoftext|>",
            ],
            target:
                "Hello, how are you?<|endoftext|>I'm doing great. How can I help you today?<|endoftext|>I'd like to show off how chat templating works!<|endoftext|>"
        ),
        // GPT-2
        Test(
            name: "GPT-2",
            chatTemplate: "{% for message in messages %}{{ message.content }}{{ eos_token }}{% endfor %}",
            data: [
                "messages": messages,
                "eos_token": "<|endoftext|>",
            ],
            target:
                "Hello, how are you?<|endoftext|>I'm doing great. How can I help you today?<|endoftext|>I'd like to show off how chat templating works!<|endoftext|>"
        ),
        // hf-internal-testing/llama-tokenizer
        Test(
            name: "hf-internal-testing/llama-tokenizer 1",
            chatTemplate:
                "{% if messages[0]['role'] == 'system' %}{% set loop_messages = messages[1:] %}{% set system_message = messages[0]['content'] %}{% elif USE_DEFAULT_PROMPT == true and not '<<SYS>>' in messages[0]['content'] %}{% set loop_messages = messages %}{% set system_message = 'DEFAULT_SYSTEM_MESSAGE' %}{% else %}{% set loop_messages = messages %}{% set system_message = false %}{% endif %}{% for message in loop_messages %}{% if (message['role'] == 'user') != (loop.index0 % 2 == 0) %}{{ raise_exception('Conversation roles must alternate user/assistant/user/assistant/...') }}{% endif %}{% if loop.index0 == 0 and system_message != false %}{% set content = '<<SYS>>\\n' + system_message + '\\n<</SYS>>\\n\\n' + message['content'] %}{% else %}{% set content = message['content'] %}{% endif %}{% if message['role'] == 'user' %}{{ bos_token + '[INST] ' + content.strip() + ' [/INST]' }}{% elif message['role'] == 'system' %}{{ '<<SYS>>\\n' + content.strip() + '\\n<</SYS>>\\n\\n' }}{% elif message['role'] == 'assistant' %}{{ ' ' + content.strip() + ' ' + eos_token }}{% endif %}{% endfor %}",
            data: [
                "messages": messagesWithSystem,
                "bos_token": "<s>",
                "eos_token": "</s>",
                "USE_DEFAULT_PROMPT": true,
            ],
            target:
                "<s>[INST] <<SYS>>\nYou are a friendly chatbot who always responds in the style of a pirate\n<</SYS>>\n\nHello, how are you? [/INST] I'm doing great. How can I help you today? </s><s>[INST] I'd like to show off how chat templating works! [/INST]"
        ),
        // hf-internal-testing/llama-tokenizer
        Test(
            name: "hf-internal-testing/llama-tokenizer 2",
            chatTemplate:
                "{% if messages[0]['role'] == 'system' %}{% set loop_messages = messages[1:] %}{% set system_message = messages[0]['content'] %}{% elif USE_DEFAULT_PROMPT == true and not '<<SYS>>' in messages[0]['content'] %}{% set loop_messages = messages %}{% set system_message = 'DEFAULT_SYSTEM_MESSAGE' %}{% else %}{% set loop_messages = messages %}{% set system_message = false %}{% endif %}{% for message in loop_messages %}{% if (message['role'] == 'user') != (loop.index0 % 2 == 0) %}{{ raise_exception('Conversation roles must alternate user/assistant/user/assistant/...') }}{% endif %}{% if loop.index0 == 0 and system_message != false %}{% set content = '<<SYS>>\\n' + system_message + '\\n<</SYS>>\\n\\n' + message['content'] %}{% else %}{% set content = message['content'] %}{% endif %}{% if message['role'] == 'user' %}{{ bos_token + '[INST] ' + content.strip() + ' [/INST]' }}{% elif message['role'] == 'system' %}{{ '<<SYS>>\\n' + content.strip() + '\\n<</SYS>>\\n\\n' }}{% elif message['role'] == 'assistant' %}{{ ' ' + content.strip() + ' ' + eos_token }}{% endif %}{% endfor %}",
            data: [
                "messages": messages,
                "bos_token": "<s>",
                "eos_token": "</s>",
                "USE_DEFAULT_PROMPT": true,
            ],
            target:
                "<s>[INST] <<SYS>>\nDEFAULT_SYSTEM_MESSAGE\n<</SYS>>\n\nHello, how are you? [/INST] I'm doing great. How can I help you today? </s><s>[INST] I'd like to show off how chat templating works! [/INST]"
        ),
        // hf-internal-testing/llama-tokenizer
        Test(
            name: "hf-internal-testing/llama-tokenizer 3",
            chatTemplate:
                "{% if messages[0]['role'] == 'system' %}{% set loop_messages = messages[1:] %}{% set system_message = messages[0]['content'] %}{% elif USE_DEFAULT_PROMPT == true and not '<<SYS>>' in messages[0]['content'] %}{% set loop_messages = messages %}{% set system_message = 'DEFAULT_SYSTEM_MESSAGE' %}{% else %}{% set loop_messages = messages %}{% set system_message = false %}{% endif %}{% for message in loop_messages %}{% if (message['role'] == 'user') != (loop.index0 % 2 == 0) %}{{ raise_exception('Conversation roles must alternate user/assistant/user/assistant/...') }}{% endif %}{% if loop.index0 == 0 and system_message != false %}{% set content = '<<SYS>>\\n' + system_message + '\\n<</SYS>>\\n\\n' + message['content'] %}{% else %}{% set content = message['content'] %}{% endif %}{% if message['role'] == 'user' %}{{ bos_token + '[INST] ' + content.strip() + ' [/INST]' }}{% elif message['role'] == 'system' %}{{ '<<SYS>>\\n' + content.strip() + '\\n<</SYS>>\\n\\n' }}{% elif message['role'] == 'assistant' %}{{ ' ' + content.strip() + ' ' + eos_token }}{% endif %}{% endfor %}",
            data: [
                "messages": [
                    [
                        "role": "user",
                        "content": "<<SYS>>\nYou are a helpful assistant\n<</SYS>> Hello, how are you?",
                    ],
                    [
                        "role": "assistant",
                        "content": "I'm doing great. How can I help you today?",
                    ],
                    [
                        "role": "user",
                        "content": "I'd like to show off how chat templating works!",
                    ],
                ],
                "bos_token": "<s>",
                "eos_token": "</s>",
                "USE_DEFAULT_PROMPT": true,
            ],
            target:
                "<s>[INST] <<SYS>>\nYou are a helpful assistant\n<</SYS>> Hello, how are you? [/INST] I'm doing great. How can I help you today? </s><s>[INST] I'd like to show off how chat templating works! [/INST]"
        ),
        // openai/whisper-large-v3
        Test(
            name: "openai/whisper-large-v3",
            chatTemplate: "{% for message in messages %}{{ message.content }}{{ eos_token }}{% endfor %}",
            data: [
                "messages": messages,
                "eos_token": "<|endoftext|>",
            ],
            target:
                "Hello, how are you?<|endoftext|>I'm doing great. How can I help you today?<|endoftext|>I'd like to show off how chat templating works!<|endoftext|>"
        ),
        // Qwen/Qwen1.5-1.8B-Chat
        Test(
            name: "Qwen/Qwen1.5-1.8B-Chat",
            chatTemplate:
                "{% for message in messages %}{% if loop.first and messages[0]['role'] != 'system' %}{{ '<|im_start|>system\nYou are a helpful assistant<|im_end|>\n' }}{% endif %}{{'<|im_start|>' + message['role'] + '\n' + message['content']}}{% if (loop.last and add_generation_prompt) or not loop.last %}{{ '<|im_end|>' + '\n'}}{% endif %}{% endfor %}{% if add_generation_prompt and messages[-1]['role'] != 'assistant' %}{{ '<|im_start|>assistant\n' }}{% endif %}",
            data: [
                "messages": messages,
                "add_generation_prompt": true,
            ],
            target:
                "<|im_start|>system\nYou are a helpful assistant<|im_end|>\n<|im_start|>user\nHello, how are you?<|im_end|>\n<|im_start|>assistant\nI\'m doing great. How can I help you today?<|im_end|>\n<|im_start|>user\nI\'d like to show off how chat templating works!<|im_end|>\n<|im_start|>assistant\n"
        ),
        // Qwen/Qwen1.5-1.8B-Chat
        Test(
            name: "Qwen/Qwen1.5-1.8B-Chat 2",
            chatTemplate:
                "{% for message in messages %}{% if loop.first and messages[0]['role'] != 'system' %}{{ '<|im_start|>system\nYou are a helpful assistant<|im_end|>\n' }}{% endif %}{{'<|im_start|>' + message['role'] + '\n' + message['content']}}{% if (loop.last and add_generation_prompt) or not loop.last %}{{ '<|im_end|>' + '\n'}}{% endif %}{% endfor %}{% if add_generation_prompt and messages[-1]['role'] != 'assistant' %}{{ '<|im_start|>assistant\n' }}{% endif %}",
            data: [
                "messages": messagesWithSystem,
                "add_generation_prompt": true,
            ],
            target:
                "<|im_start|>system\nYou are a friendly chatbot who always responds in the style of a pirate<|im_end|>\n<|im_start|>user\nHello, how are you?<|im_end|>\n<|im_start|>assistant\nI\'m doing great. How can I help you today?<|im_end|>\n<|im_start|>user\nI\'d like to show off how chat templating works!<|im_end|>\n<|im_start|>assistant\n"
        ),
        // Qwen/Qwen1.5-1.8B-Chat
        Test(
            name: "Qwen/Qwen1.5-1.8B-Chat 3",
            chatTemplate:
                "{% for message in messages %}{% if loop.first and messages[0]['role'] != 'system' %}{{ '<|im_start|>system\nYou are a helpful assistant<|im_end|>\n' }}{% endif %}{{'<|im_start|>' + message['role'] + '\n' + message['content']}}{% if (loop.last and add_generation_prompt) or not loop.last %}{{ '<|im_end|>' + '\n'}}{% endif %}{% endfor %}{% if add_generation_prompt and messages[-1]['role'] != 'assistant' %}{{ '<|im_start|>assistant\n' }}{% endif %}",
            data: [
                "messages": messagesWithSystem
            ],
            target:
                "<|im_start|>system\nYou are a friendly chatbot who always responds in the style of a pirate<|im_end|>\n<|im_start|>user\nHello, how are you?<|im_end|>\n<|im_start|>assistant\nI\'m doing great. How can I help you today?<|im_end|>\n<|im_start|>user\nI\'d like to show off how chat templating works!"
        ),
        // THUDM/chatglm3-6b
        Test(
            name: "THUDM/chatglm3-6b",
            chatTemplate:
                "{% for message in messages %}{% if loop.first %}[gMASK]sop<|{{ message['role'] }}|>\n {{ message['content'] }}{% else %}<|{{ message['role'] }}|>\n {{ message['content'] }}{% endif %}{% endfor %}{% if add_generation_prompt %}<|assistant|>{% endif %}",
            data: [
                "messages": messagesWithSystem
            ],
            target:
                "[gMASK]sop<|system|>\n You are a friendly chatbot who always responds in the style of a pirate<|user|>\n Hello, how are you?<|assistant|>\n I\'m doing great. How can I help you today?<|user|>\n I\'d like to show off how chat templating works!"
        ),
        // google/gemma-2b-it
        Test(
            name: "google/gemma-2b-it",
            chatTemplate:
                "{{ bos_token }}{% if messages[0]['role'] == 'system' %}{{ raise_exception('System role not supported') }}{% endif %}{% for message in messages %}{% if (message['role'] == 'user') != (loop.index0 % 2 == 0) %}{{ raise_exception('Conversation roles must alternate user/assistant/user/assistant/...') }}{% endif %}{% if (message['role'] == 'assistant') %}{% set role = 'model' %}{% else %}{% set role = message['role'] %}{% endif %}{{ '<start_of_turn>' + role + '\n' + message['content'] | trim + '<end_of_turn>\n' }}{% endfor %}{% if add_generation_prompt %}{{'<start_of_turn>model\n'}}{% endif %}",
            data: [
                "messages": messages
            ],
            target:
                "<start_of_turn>user\nHello, how are you?<end_of_turn>\n<start_of_turn>model\nI\'m doing great. How can I help you today?<end_of_turn>\n<start_of_turn>user\nI\'d like to show off how chat templating works!<end_of_turn>\n"
        ),
        // Qwen/Qwen2.5-0.5B-Instruct
        Test(
            name: "Qwen/Qwen2.5-0.5B-Instruct",
            chatTemplate:
                "{%- if tools %}\n    {{- '<|im_start|>system\\n' }}\n    {%- if messages[0]['role'] == 'system' %}\n        {{- messages[0]['content'] }}\n    {%- else %}\n        {{- 'You are Qwen, created by Alibaba Cloud. You are a helpful assistant.' }}\n    {%- endif %}\n    {{- \"\\n\\n# Tools\\n\\nYou may call one or more functions to assist with the user query.\\n\\nYou are provided with function signatures within <tools></tools> XML tags:\\n<tools>\" }}\n    {%- for tool in tools %}\n        {{- \"\\n\" }}\n        {{- tool | tojson }}\n    {%- endfor %}\n    {{- \"\\n</tools>\\n\\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\\n<tool_call>\\n{\\\"name\\\": <function-name>, \\\"arguments\\\": <args-json-object>}\\n</tool_call><|im_end|>\\n\" }}\n{%- else %}\n    {%- if messages[0]['role'] == 'system' %}\n        {{- '<|im_start|>system\\n' + messages[0]['content'] + '<|im_end|>\\n' }}\n    {%- else %}\n        {{- '<|im_start|>system\\nYou are Qwen, created by Alibaba Cloud. You are a helpful assistant.<|im_end|>\\n' }}\n    {%- endif %}\n{%- endif %}\n{%- for message in messages %}\n    {%- if (message.role == \"user\") or (message.role == \"system\" and not loop.first) or (message.role == \"assistant\" and not message.tool_calls) %}\n        {{- '<|im_start|>' + message.role + '\\n' + message.content + '<|im_end|>' + '\\n' }}\n    {%- elif message.role == \"assistant\" %}\n        {{- '<|im_start|>' + message.role }}\n        {%- if message.content %}\n            {{- '\\n' + message.content }}\n        {%- endif %}\n        {%- for tool_call in message.tool_calls %}\n            {%- if tool_call.function is defined %}\n                {%- set tool_call = tool_call.function %}\n            {%- endif %}\n            {{- '\\n<tool_call>\\n{\"name\": \"' }}\n            {{- tool_call.name }}\n            {{- '\", \"arguments\": ' }}\n            {{- tool_call.arguments | tojson }}\n            {{- '}\\n</tool_call>' }}\n        {%- endfor %}\n        {{- '<|im_end|>\\n' }}\n    {%- elif message.role == \"tool\" %}\n        {%- if (loop.index0 == 0) or (messages[loop.index0 - 1].role != \"tool\") %}\n            {{- '<|im_start|>user' }}\n        {%- endif %}\n        {{- '\\n<tool_response>\\n' }}\n        {{- message.content }}\n        {{- '\\n</tool_response>' }}\n        {%- if loop.last or (messages[loop.index0 + 1].role != \"tool\") %}\n            {{- '<|im_end|>\\n' }}\n        {%- endif %}\n    {%- endif %}\n{%- endfor %}\n{%- if add_generation_prompt %}\n    {{- '<|im_start|>assistant\\n' }}\n{%- endif %}\n",
            data: [
                "messages": messages
            ],
            target:
                "<|im_start|>system\nYou are Qwen, created by Alibaba Cloud. You are a helpful assistant.<|im_end|>\n<|im_start|>user\nHello, how are you?<|im_end|>\n<|im_start|>assistant\nI\'m doing great. How can I help you today?<|im_end|>\n<|im_start|>user\nI\'d like to show off how chat templating works!<|im_end|>\n"
        ),
        // Llama-3.2-11B-Vision-Instruct: text chat only
        Test(
            name: "Llama-3.2-11B-Vision-Instruct: text chat only",
            chatTemplate: llama3_2visionChatTemplate,
            data: [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "Hello, how are you?"
                            ] as [String: Any]
                        ] as [[String: Any]]
                    ] as [String: Any],
                    [
                        "role": "assistant",
                        "content": [
                            [
                                "type": "text",
                                "text": "I'm doing great. How can I help you today?"
                            ] as [String: Any]
                        ] as [[String: Any]]
                    ] as [String: Any],
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "I'd like to show off how chat templating works!"
                            ] as [String: Any]
                        ] as [[String: Any]]
                    ] as [String: Any]
                ] as [[String: Any]] as Any,
                "bos_token": "<s>" as Any,
                "date_string": "26 Jul 2024" as Any,
                "tools_in_user_message": true as Any,
                "system_message": "You are a helpful assistant." as Any,
                "add_generation_prompt": true as Any
            ],
            target: "<s>\n<|start_header_id|>system<|end_header_id|>\n\nCutting Knowledge Date: December 2023\nToday Date: 26 Jul 2024\n\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nHello, how are you?<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\nI'm doing great. How can I help you today?<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nI'd like to show off how chat templating works!<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
        ),
        // Llama-3.2-11B-Vision-Instruct: with images
        Test(
            name: "Llama-3.2-11B-Vision-Instruct: with images",
            chatTemplate: llama3_2visionChatTemplate,
            data: [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "What's in this image?"
                            ] as [String: Any],
                            [
                                "type": "image",
                                "image": "base64_encoded_image_data"
                            ] as [String: Any]
                        ] as [[String: Any]]
                    ] as [String: Any]
                ] as [[String: Any]] as Any,
                "bos_token": "<s>" as Any,
                "add_generation_prompt": true as Any
            ],
            target: "<s>\n<|start_header_id|>system<|end_header_id|>\n\nCutting Knowledge Date: December 2023\nToday Date: 26 Jul 2024\n\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nWhat's in this image?<|image|><|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
        ),
        // Qwen2-VL text only
        Test(
            name: "Qwen2-VL-7B-Instruct: text only",
            chatTemplate: qwen2VLChatTemplate,
            data: [
                "messages": messages,
                "add_generation_prompt": true
            ],
            target: """
    <|im_start|>system
    You are a helpful assistant.<|im_end|>
    <|im_start|>user
    Hello, how are you?<|im_end|>
    <|im_start|>assistant
    I'm doing great. How can I help you today?<|im_end|>
    <|im_start|>user
    I'd like to show off how chat templating works!<|im_end|>
    <|im_start|>assistant

    """
        ),
        // Qwen2-VL with images
        Test(
            name: "Qwen2-VL-7B-Instruct: with images",
            chatTemplate: qwen2VLChatTemplate,
            data: [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "What's in this image?"
                            ] as [String: String],
                            [
                                "type": "image",
                                "image_url": "example.jpg"
                            ] as [String: String]
                        ] as [[String: String]]
                    ] as [String: Any]
                ] as [[String: Any]],
                "add_generation_prompt": true,
                "add_vision_id": true
            ],
            target: """
    <|im_start|>system
    You are a helpful assistant.<|im_end|>
    <|im_start|>user
    What's in this image?Picture 1: <|vision_start|><|image_pad|><|vision_end|><|im_end|>
    <|im_start|>assistant

    """
        ),
        // Qwen2-VL with video
        Test(
            name: "Qwen2-VL-7B-Instruct: with video",
            chatTemplate: qwen2VLChatTemplate,
            data: [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "What's happening in this video?"
                            ] as [String: String],
                            [
                                "type": "video",
                                "video_url": "example.mp4"
                            ] as [String: String]
                        ] as [[String: String]]
                    ] as [String: Any]
                ] as [[String: Any]],
                "add_generation_prompt": true,
                "add_vision_id": true
            ],
            target: """
    <|im_start|>system
    You are a helpful assistant.<|im_end|>
    <|im_start|>user
    What's happening in this video?Video 1: <|vision_start|><|video_pad|><|vision_end|><|im_end|>
    <|im_start|>assistant

    """
        )
    ]

    func testDefaultTemplates() throws {
        for test in defaultTemplates {
            print("Testing \(test.name)")
            let template = try Template(test.chatTemplate)
            let result = try template.render(test.data)
            print(result)
            XCTAssertEqual(result.debugDescription, test.target.debugDescription)
        }
    }

    // TODO: Get testLlama32ToolCalls working

//    func testLlama32ToolCalls() throws {
//        let tools = [
//            [
//                "name": "get_current_weather",
//                "description": "Get the current weather in a given location",
//                "parameters": [
//                    "type": "object",
//                    "properties": [
//                        "location": [
//                            "type": "string",
//                            "description": "The city and state, e.g. San Francisco, CA"
//                        ],
//                        "unit": [
//                            "type": "string",
//                            "enum": ["celsius", "fahrenheit"]
//                        ]
//                    ],
//                    "required": ["location"]
//                ]
//            ]
//        ]
//
//        let messages: [[String: Any]] = [
//            [
//                "role": "user",
//                "content": "What's the weather like in San Francisco?"
//            ],
//            [
//                "role": "assistant",
//                "tool_calls": [
//                    [
//                        "function": [
//                            "name": "get_current_weather",
//                            "arguments": "{\"location\": \"San Francisco, CA\", \"unit\": \"celsius\"}"
//                        ]
//                    ]
//                ]
//            ],
//            [
//                "role": "tool",
//                "content": "{\"temperature\": 22, \"unit\": \"celsius\", \"description\": \"Sunny\"}"
//            ],
//            [
//                "role": "assistant",
//                "content": "The weather in San Francisco is sunny with a temperature of 22°C."
//            ]
//        ]
//
//        let template = try Template(llama3_2visionChatTemplate)
//        let result = try template.render([
//            "messages": messages,
//            "tools": tools,
//            "bos_token": "<s>",
//            "date_string": "26 Jul 2024",
//            "add_generation_prompt": true
//        ])
//
//        print(result) // Debugging for comparison with expected
//
//        // TODO: Replace with printed result if it works
//        let expected = """
//        <s>
//        <|start_header_id|>system<|end_header_id|>
//        
//        Environment: ipython
//        Cutting Knowledge Date: December 2023
//        Today Date: 26 Jul 2024
//        
//        <|eot_id|><|start_header_id|>user<|end_header_id|>
//        
//        What's the weather like in San Francisco?<|eot_id|><|start_header_id|>assistant<|end_header_id|>
//        
//        {"name": "get_current_weather", "parameters": {"location": "San Francisco, CA", "unit": "celsius"}}<|eot_id|><|start_header_id|>ipython<|end_header_id|>
//        
//        {"temperature": 22, "unit": "celsius", "description": "Sunny"}<|eot_id|><|start_header_id|>assistant<|end_header_id|>
//        
//        The weather in San Francisco is sunny with a temperature of 22°C.<|eot_id|><|start_header_id|>assistant<|end_header_id|>
//        
//        """
//
//        XCTAssertEqual(result, expected)
//    }
}
