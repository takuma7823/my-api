from fastapi import FastAPI

app = FastAPI()
todos = []
next_id = 1


@app.get("/")
def read_root():
    return {"message": "Hello, World!"}


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/todos")
def get_todos():
    return todos


@app.post("/todos")
def create_todo(title: str):
    global next_id
    todo = {"id": next_id, "title": title, "done": False}
    todos.append(todo)
    next_id += 1
    return todo


@app.delete("/todos/{todo_id}")
def delete_todo(todo_id: int):
    global todos
    todos = [t for t in todos if t["id"] != todo_id]
    return {"message": "deleted"}
