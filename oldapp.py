import os
from flask import Flask
from google.cloud import bigquery
from tabulate import tabulate

app = Flask(__name__)
client = bigquery.Client()

WORD = os.environ["WORD"]
QUERY = """SELECT
    corpus,
    SUM(word_count) as total_words
FROM `bigquery-public-data.samples.shakespeare`
WHERE word = 'the'
GROUP BY corpus
ORDER BY total_words DESC"""

@app.route("/")
def index():
    results = list(client.query(QUERY).result())
    table_str = tabulate(results, headers="keys", tablefmt="github")
    return f"<h4>Amount of times '{WORD}' appears per corpus</h4><pre>{table_str}</pre>"

if __name__ == "__main__":
    app.run(debug=True)
