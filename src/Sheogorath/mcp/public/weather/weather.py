"""
Weather tool logic
"""
import os
import json
from datetime import datetime

import pandas as pd
from dotenv import load_dotenv
from openmeteo import OpenMeteo

cities = pd.read_csv("public/data/uscities.csv")

def get_weather_forecast(city: str) -> str:
    """Get the weather for a city"""
    longitude, latitude = cities[cities["city"] == city].iloc[0][["longitude", "latitude"]]
    openmeteo = OpenMeteo(api_key=os.getenv("OPENMETEO_API_KEY"))
    response = openmeteo.forecast(
        latitude=latitude,
        longitude=longitude,
        hourly=["temperature_2m", "relative_humidity_2m", "wind_speed_10m"],
    )
    return response.json()

def save_file(data: dict, filename: str) -> str:
    """Save the weather data to a file"""
    with open(filename, "w") as f:
        json.dump(data, f, indent=4)

def get_weather(city: str) -> str:
    """Get the weather for a city"""
    dt = datetime.now().strftime('%Y-%m-%d')
    if os.path.exists(f"public/data/weather/{dt}/{city}.json"):
        with open(f"public/data/weather/{dt}/{city}.json", "r") as f:
            return json.load(f)
    else:
        response = get_weather_forecast(city)
        if not os.path.exists(f"public/data/weather/{dt}"):
            os.makedirs(f"public/data/weather/{dt}")
        with open(f"public/data/weather/{dt}/{city}.json", "w") as f:
            json.dump(response, f, indent=4)
        return response
