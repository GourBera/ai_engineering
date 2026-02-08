from smolagents import ToolCallingAgent, tool, ChatMessage
import json

# Create a mock model that doesn't require API keys
class MockWeatherModel:
    """A mock language model for testing without API authentication."""
    
    def __init__(self, model_id="mock-weather"):
        self.model_id = model_id
    
    def generate(self, messages, stop_sequences=None, tools_to_call_from=None, **kwargs):
        """Generate a mock response."""
        # Create a proper ChatMessage object with all required attributes
        chat_message = ChatMessage(
            role="assistant",
            content="I will help you get the weather information and save it."
        )
        # Add required attributes
        chat_message.tool_calls = None
        chat_message.token_usage = type('TokenUsage', (), {
            'prompt_tokens': 10,
            'completion_tokens': 10,
            'input_tokens': 10,
            'output_tokens': 10
        })()
        return chat_message
    
    def parse_tool_calls(self, assistant_message):
        """Parse tool calls from model output (mock implementation)."""
        return []  # No tool calls for mock model

# Initialize the mock model
model = MockWeatherModel()

# Define tools that agents can use
@tool
def get_weather(city: str) -> str:
    """Get weather information for a city.
    
    Args:
        city: The name of the city to get weather for.
    """
    return f"Weather in {city}: Sunny, 75°F"

@tool
def save_data(key: str, value: str) -> str:
    """Save data to memory.
    
    Args:
        key: The key to store the data under.
        value: The value to store.
    """
    memory[key] = value
    return f"Saved: {key} = {value}"

# Global shared state
memory = {}

# Create a SmoLAgent
class WeatherAgent(ToolCallingAgent):
    def __init__(self):
        super().__init__(
            tools=[get_weather, save_data],  # Tools this agent can use
            model=model,                     # Small language model
            name="weather_assistant"         # Agent identifier
        )

    def ask_weather(self, city: str):
        """Agent processes a weather request."""
        response = self.run(
            f"Get weather for {city} and save it. "
            f"Respond with JSON: {{'weather': 'description', 'saved': true/false}}"
        )
        return response

# Usage
agent = WeatherAgent()
result = agent.ask_weather("New York")
print(result)  # Agent uses tools automatically to get and save weather