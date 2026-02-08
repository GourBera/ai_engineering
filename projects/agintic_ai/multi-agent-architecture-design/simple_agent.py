"""
Simple agent example without requiring API keys.
This demonstrates the concept of tool-using agents.
"""

import json


# Define tools that agents can use
def get_weather(city: str) -> str:
    """Get weather information for a city.
    
    Args:
        city: The name of the city to get weather for.
    
    Returns:
        A string with weather information.
    """
    weather_data = {
        "New York": "Sunny, 75°F",
        "London": "Cloudy, 60°F",
        "Tokyo": "Rainy, 68°F",
        "Sydney": "Clear, 82°F"
    }
    return f"Weather in {city}: {weather_data.get(city, 'Unknown')}"


def save_data(key: str, value: str) -> str:
    """Save data to memory.
    
    Args:
        key: The key to store the data under.
        value: The value to store.
    
    Returns:
        Confirmation message.
    """
    memory[key] = value
    return f"Saved: {key} = {value}"


# Global shared state
memory = {}


class SimpleWeatherAgent:
    """A simple agent that uses tools without requiring an LLM."""
    
    def __init__(self, name: str = "weather_assistant"):
        self.name = name
        self.tools = {
            "get_weather": get_weather,
            "save_data": save_data
        }
    
    def run(self, task: str):
        """Execute a task using available tools.
        
        Args:
            task: The task description.
        
        Returns:
            The result of executing the task.
        """
        print(f"\n{'='*60}")
        print(f"Agent: {self.name}")
        print(f"Task: {task}")
        print(f"{'='*60}\n")
        
        # For demo purposes, manually execute tools based on the task
        if "weather" in task.lower() and "New York" in task:
            print("Step 1: Calling get_weather tool...")
            weather_result = get_weather("New York")
            print(f"Result: {weather_result}\n")
            
            print("Step 2: Calling save_data tool...")
            save_result = save_data("new_york_weather", weather_result)
            print(f"Result: {save_result}\n")
            
            # Return JSON as expected
            return json.dumps({
                "weather": weather_result,
                "saved": True,
                "timestamp": "2026-02-06"
            })
        
        return json.dumps({"status": "task_unknown"})


# Usage
if __name__ == "__main__":
    agent = SimpleWeatherAgent()
    result = agent.run("Get weather for New York and save it.")
    print("\nFinal Result:")
    print(result)
    
    print("\n\nMemory contents:")
    print(json.dumps(memory, indent=2))
