from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy.orm import Session

from app import models, schemas
from app.bq import log_todo_event
from app.db import Base, engine, get_db

Base.metadata.create_all(bind=engine)

app = FastAPI()


@app.get("/")
def read_root():
    return {"message": "Hello, World!"}


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/todos", response_model=list[schemas.TodoRead])
def get_todos(db: Session = Depends(get_db)):
    return db.query(models.Todo).all()


@app.post("/todos", response_model=schemas.TodoRead)
def create_todo(payload: schemas.TodoCreate, db: Session = Depends(get_db)):
    todo = models.Todo(title=payload.title)
    db.add(todo)
    db.commit()
    db.refresh(todo)
    log_todo_event(todo.id, "created", todo.title)
    return todo


@app.delete("/todos/{todo_id}")
def delete_todo(todo_id: int, db: Session = Depends(get_db)):
    todo = db.query(models.Todo).filter(models.Todo.id == todo_id).first()
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")
    title = todo.title
    db.delete(todo)
    db.commit()
    log_todo_event(todo_id, "deleted", title)
    return {"message": "deleted"}