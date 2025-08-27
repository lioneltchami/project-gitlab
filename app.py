import os
from flask import Flask  
from google.cloud import bigquery
from tabulate import tabulate
import logging 

logging.basicConfig(level=logging.INFO) # info | warning p3 | error p2 | critical p1
logger = logging.getLogger(__name__)

app = Flask(__name__)

try:
    client = bigquery.Client()
    logger.info("BigQuery client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize BigQuery client: {e}")
    client = None


WORD = os.environ.get("WORD", "the", "AND", "tea", "COFFEE")
logger.info(f"Configured to search for word: '{WORD}'")


QUERY = f"""SELECT
    corpus,
    SUM(word_count) as total_words
FROM `bigquery-public-data.samples.shakespeare`
WHERE word = '{WORD}'
GROUP BY corpus
ORDER BY total_words DESC"""

@app.route("/health")
def health():
    """Health check endpoint"""
    if client is None:
        return {"status": "unhealthy", "reason": "BigQuery client not initialized"}, 503
    return {"status": "healthy", "word": WORD}, 200

@app.route("/")
def index():
    """Main endpoint to display word count results"""
    if client is None:
        return "<h4>Service Unavailable</h4><p>BigQuery client not available</p>", 503 # len(results)
    
    try:
        logger.info(f"Executing query for word: '{WORD}'")
        results = list(client.query(QUERY).result())
        logger.info(f"Query returned {len(results)} results")
        
        if not results:
            return f"<h4>No results found for word '{WORD}'</h4>"
        
        table_str = tabulate(results, headers="keys", tablefmt="github")
        return f"<h4>Amount of times '{WORD}' appears per corpus</h4><pre>{table_str}</pre>"
    
    except Exception as e:
        logger.error(f"Error executing query: {e}")
        return f"<h4>Error</h4><p>Failed to execute query: {str(e)}</p>", 500

@app.route("/metrics")
def metrics():
    """Basic metrics endpoint for monitoring"""
    return {
        "word": WORD,
        "status": "running",
        "bigquery_available": client is not None
    }

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=os.environ.get("FLASK_ENV") == "development")