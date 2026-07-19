# Mermaid Syntax Cheatsheet

A compact reference for generating valid Mermaid diagrams. ALWAYS wrap node text containing
spaces, punctuation, or special characters in **double quotes**.

## Flowchart (most common)

```mermaid
flowchart TD
    A["Start"] --> B{"Decision?"}
    B -- Yes --> C["Process"]
    B -- No --> D["End"]
    C --> D
```

Directions: `TD` (top-down), `LR` (left-right), `BT`, `RL`.

Node shapes: `A["text"]` rect, `B("text")` rounded, `C{"text"}` rhombus, `D[("DB")]` cylinder, `E(("circle"))`.

Arrows: `-->`, `---`, `-.->` (dotted), `==>` (thick), `--label-->` (with label).

## Sequence Diagram

```mermaid
sequenceDiagram
    participant Alice
    participant Bob
    Alice->>Bob: Hello
    Bob-->>Alice: Hi back
    Note right of Bob: Bob thinks
```

## Class Diagram

```mermaid
classDiagram
    class Animal {
      +String name
      +eat()
    }
    Animal <|-- Dog
```

## State Diagram

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Running: start
    Running --> Idle: stop
```

## ER Diagram

```mermaid
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
```

## Gantt

```mermaid
gantt
    title Project
    dateFormat YYYY-MM-DD
    section Phase 1
    Design     :a1, 2026-01-01, 7d
    Implement  :after a1, 14d
```

## Common pitfalls

- Wrap node text containing spaces or punctuation in `"..."`. Bad: `A[Step 1?]`. Good: `A["Step 1?"]`.
- Avoid line breaks inside node text — use `<br/>` instead.
- Subgraph titles are quoted: `subgraph "My Group"`.
- Comment lines start with `%%`.
- Reserved words (`end`, `class`, `style`) need quoting if used as text.
