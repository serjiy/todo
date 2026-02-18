from flask import Flask, render_template, request, redirect, url_for
from pymongo import MongoClient
from bson.objectid import ObjectId
from bson.errors import InvalidId
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import Counter  # ← добавляем стандартный Counter
import os

# Конфигурация MongoDB
mongodb_host = os.environ.get('MONGO_HOST', 'mongo')
mongodb_port = int(os.environ.get('MONGO_PORT', '27017'))

client = MongoClient(mongodb_host, mongodb_port)
db = client.camp2016
todos = db.todo

app = Flask(__name__)
title = "TODO with Flask"
heading = "ToDo Reminder"

# Prometheus HTTP-метрики (автоматические)
metrics = PrometheusMetrics(app, group_by='url_rule')

# Кастомные метрики через prometheus_client
tasks_created = Counter(
    'todo_tasks_created_total',
    'Total number of tasks created',
    ['priority']  # ← labels здесь
)

tasks_completed = Counter(
    'todo_tasks_completed_total',
    'Total number of tasks marked as completed'
)

@app.route('/health')
def health():
    try:
        client.admin.command('ping')
        return "OK", 200
    except Exception:
        return "Database unavailable", 503

def redirect_url():
    return request.args.get('next') or request.referrer or url_for('index')

@app.route("/list")
def lists():
    todos_l = todos.find()
    a1 = "active"
    return render_template('index.html', a1=a1, todos=todos_l, t=title, h=heading)

@app.route("/")
@app.route("/uncompleted")
def tasks():
    todos_l = todos.find({"done": "no"})
    a2 = "active"
    return render_template('index.html', a2=a2, todos=todos_l, t=title, h=heading)

@app.route("/completed")
def completed():
    todos_l = todos.find({"done": "yes"})
    a3 = "active"
    return render_template('index.html', a3=a3, todos=todos_l, t=title, h=heading)

@app.route("/done")
def done():
    id = request.values.get("_id")
    task = todos.find_one({"_id": ObjectId(id)})
    if task is None:
        return redirect(redirect_url())
    if task["done"] == "yes":
        todos.update_one({"_id": ObjectId(id)}, {"$set": {"done": "no"}})
    else:
        todos.update_one({"_id": ObjectId(id)}, {"$set": {"done": "yes"}})
        tasks_completed.inc()
    redir = redirect_url()
    return redirect(redir)

@app.route("/action", methods=['POST'])
def action():
    name = request.values.get("name")
    desc = request.values.get("desc")
    date = request.values.get("date")
    pr = request.values.get("pr") or "none"

    todos.insert_one({"name": name, "desc": desc, "date": date, "pr": pr, "done": "no"})

    # Правильный inc с label
    tasks_created.labels(priority=pr).inc()

    return redirect("/list")

@app.route("/remove")
def remove():
    key = request.values.get("_id")
    todos.delete_one({"_id": ObjectId(key)})
    return redirect("/")

@app.route("/update")
def update():
    id = request.values.get("_id")
    task = todos.find({"_id": ObjectId(id)})
    return render_template('update.html', tasks=task, h=heading, t=title)

@app.route("/action3", methods=['POST'])
def action3():
    name = request.values.get("name")
    desc = request.values.get("desc")
    date = request.values.get("date")
    pr = request.values.get("pr")
    id = request.values.get("_id")
    todos.update_one({"_id": ObjectId(id)}, {'$set': {"name": name, "desc": desc, "date": date, "pr": pr}})
    return redirect("/")

@app.route("/search", methods=['GET'])
def search():
    key = request.values.get("key")
    refer = request.values.get("refer")
    if refer == "id":
        try:
            todos_l = todos.find({refer: ObjectId(key)})
            if todos_l.count() == 0:
                return render_template('index.html', a2="active", todos=[], t=title, h=heading, error="No such ObjectId is present")
        except InvalidId:
            return render_template('index.html', a2="active", todos=[], t=title, h=heading, error="Invalid ObjectId format given")
    else:
        todos_l = todos.find({refer: key})
    return render_template('searchlist.html', todos=todos_l, t=title, h=heading)

@app.route("/about")
def about():
    return render_template('credits.html', t=title, h=heading)

if __name__ == "__main__":
    env = os.environ.get('FLASK_ENV', 'development')
    port = int(os.environ.get('PORT', 5000))
    debug = env != 'production'
    app.run(host='0.0.0.0', port=port, debug=debug)
