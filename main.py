# type: ignore
from fastapi import FastAPI, HTTPException, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
import requests
from google import genai
from google.genai import types
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import os
from dotenv import load_dotenv

# --- 1. SESSION & GENAI SDK SETUP ---
session = requests.Session()
retries = Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504])
session.mount('https://', HTTPAdapter(max_retries=retries))

HEADERS = {'User-Agent': 'SugarLens - Windows - Version 1.0 - reape_dev'}
load_dotenv() # This loads the variables from .env
API_KEY = os.getenv("GEMINI_API_KEY")

client = genai.Client(api_key=API_KEY)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 2. REUSABLE SEARCH LOGIC ---
def fetch_sugar_logic(food_name: str):
    """Hits the Open Food Facts API and returns product name and sugar content."""
    search_url = "https://world.openfoodfacts.org/cgi/search.pl"
    params = {
        "search_terms": food_name,
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "page_size": 5
    }

    try:
        response = session.get(search_url, params=params, headers=HEADERS, timeout=10)
        response.raise_for_status()
        data = response.json()

        if data.get('products'):
            for product in data['products']:
                nutriments = product.get('nutriments', {})
                sugar = nutriments.get('sugars_100g')
                if sugar is not None:
                    return {
                        "product_name": product.get('product_name', food_name),
                        "sugar_100g": sugar
                    }

        return {"product_name": food_name, "sugar_100g": "No Data"}
    except Exception as e:
        return {"product_name": food_name, "sugar_100g": "N/A"}

# --- 3. API ROUTES ---

@app.get("/analyze/{food_name}")
def analyze_text(food_name: str):
    return fetch_sugar_logic(food_name)

@app.post("/upload")
async def upload_image(file: UploadFile = File(...)):
    """Modernized 2025 image upload logic using the google-genai SDK."""
    try:
        contents = await file.read()
        prompt = (
            "Identify the food in this image. "
            "Return exactly 3 names of the most likely food items, "
            "separated by commas only. No extra text."
        )

        # The new SDK takes a list of content parts
        # We use types.Part.from_bytes to handle the image correctly
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[
                types.Part.from_bytes(data=contents, mime_type="image/jpeg"),
                prompt
            ]
        )

        if not response.text:
            return {"suggestions": [], "error": "AI could not identify the image."}
        # Split the CSV string from the AI
        food_names = [name.strip() for name in response.text.split(',')]
        suggestions = []
        for name in food_names[:3]:
            # Fetch real-world sugar data for the AI's guesses
            data = fetch_sugar_logic(name)
            suggestions.append({
                "label": name,
                "confidence": "AI",
                "sugar": data['sugar_100g']
            })
        return {"suggestions": suggestions}
    except Exception as e:
        print(f"GenAI SDK Error: {e}")
        return {"error": str(e), "suggestions": []}

if __name__ == "__main__":
    import uvicorn
    # Make sure to run on 0.0.0.0 so your Flutter app can see it
    uvicorn.run(app, host="0.0.0.0", port=8000)
