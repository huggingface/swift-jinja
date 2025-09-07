//
//  ToolSpecs.swift
//  Jinja
//
//  Created by Anthony DePasquale on 02.01.2025.
//

import OrderedCollections

struct ToolSpec {
    static let getCurrentWeather = OrderedDictionary(uniqueKeysWithValues: [
        ("type", "function") as (String, any Sendable),
        (
            "function",
            OrderedDictionary(uniqueKeysWithValues: [
                ("name", "get_current_weather") as (String, any Sendable),
                ("description", "Get the current weather in a given location") as (String, any Sendable),
                (
                    "parameters",
                    OrderedDictionary(uniqueKeysWithValues: [
                        ("type", "object") as (String, any Sendable),
                        (
                            "properties",
                            OrderedDictionary(uniqueKeysWithValues: [
                                (
                                    "location",
                                    OrderedDictionary(uniqueKeysWithValues: [
                                        ("type", "string") as (String, any Sendable),
                                        ("description", "The city and state, e.g. San Francisco, CA")
                                            as (String, any Sendable),
                                    ])
                                ) as (String, any Sendable),
                                (
                                    "unit",
                                    OrderedDictionary(uniqueKeysWithValues: [
                                        ("type", "string") as (String, any Sendable),
                                        ("enum", ["celsius", "fahrenheit"]) as (String, any Sendable),
                                    ])
                                ) as (String, any Sendable),
                            ])
                        ) as (String, any Sendable),
                        ("required", ["location"]) as (String, any Sendable),
                    ])
                ) as (String, any Sendable),
            ])
        ) as (String, any Sendable),
    ])
}
