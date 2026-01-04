# type: ignore
from fastapi import FastAPI, HTTPException, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
import requests
from google import genai
from google.genai import types
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import os
import json
from dotenv import load_dotenv

# --- 1. SESSION & GENAI SDK SETUP ---
session = requests.Session()
retries = Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504])
session.mount('https://', HTTPAdapter(max_retries=retries))

HEADERS = {'User-Agent': 'SugarLens - Windows - Version 1.0 - reape_dev'}
load_dotenv() 
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

# --- 2. DATABASE SEARCH LOGIC (Open Food Facts) ---
def fetch_from_db(food_name: str):
    """Hits the Open Food Facts API and returns raw product data."""
    search_url = "https://world.openfoodfacts.org/cgi/search.pl"
    params = {
        "search_terms": food_name,
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "page_size": 3 # Look at top 3 to find a better match
    }

    try:
        response = session.get(search_url, params=params, headers=HEADERS, timeout=10)
        response.raise_for_status()
        data = response.json()
        return data.get('products', [])
    except Exception:
        return []

# --- 3. API ROUTES ---

@app.get("/analyze/{food_name}")
def analyze_text(food_name: str):
    """Hybrid Strategy: Database first, Gemini as Referee."""
    products = fetch_from_db(food_name)
    
    db_name = "No Data"
    db_sugar = "N/A"
    
    if products:
        # Check the first product
        top_hit = products[0]
        db_name = top_hit.get('product_name', food_name)
        db_sugar = top_hit.get('nutriments', {}).get('sugars_100g')

        # --- TRUST CHECK ---
        # If the search term is clearly in the product name, return DB data immediately (Saves Quota)
        if food_name.lower() in db_name.lower() and db_sugar is not None:
            return {"product_name": db_name, "sugar_100g": db_sugar, "source": "database"}

    # --- GEMINI REFEREE STEP ---
    # If we are here, the database was empty OR returned something suspicious (like Cappy for Coke)
    prompt = (
        f"A user searched for '{food_name}'. The database returned '{db_name}' with {db_sugar}g sugar. "
        "If this database result is inaccurate for a standard version of the search term, provide the "
        "average sugar content for the correct item per 100g. "
        "Return ONLY a JSON object: {\"product_name\": \"name\", \"sugar_100g\": value}"
    )

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt
        )
        # Parse the AI response
        ai_text = response.text.replace('```json', '').replace('```', '').strip()
        ai_data = json.loads(ai_text)
        ai_data["source"] = "gemini_ai"
        return ai_data
    except Exception as e:
        # If AI fails, return whatever the database had
        return {"product_name": db_name, "sugar_100g": db_sugar if db_sugar else 0.0, "source": "fallback"}

@app.post("/upload")
async def upload_image(file: UploadFile = File(...)):
    """AI image analysis remains high-priority Gemini usage."""
    try:
        contents = await file.read()
        prompt = (
            "Identify the food in this image. "
            "Return exactly 3 names of the most likely food items, "
            "separated by commas only. No extra text."
        )

        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[
                types.Part.from_bytes(data=contents, mime_type="image/jpeg"),
                prompt
            ]
        )

        if not response.text:
            return {"suggestions": [], "error": "AI could not identify the image."}
        
        food_names = [name.strip() for name in response.text.split(',')]
        suggestions = []
        for name in food_names[:3]:
            # We use the text analysis logic for the AI's guesses too
            data = analyze_text(name)
            suggestions.append({
                "label": data['product_name'],
                "confidence": "AI",
                "sugar": data['sugar_100g']
            })
        return {"suggestions": suggestions}
    except Exception as e:
        print(f"GenAI SDK Error: {e}")
        return {"error": str(e), "suggestions": []}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
    