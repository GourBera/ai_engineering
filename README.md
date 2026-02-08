# Python Monorepo for Data Engineering

This monorepo contains multiple data engineering and AI subprojects, each with its own isolated environment and best-practice structure.

## Structure
- projects/
  - agintic_ai/: Notebooks on prompting, reasoning, and planning
  - airflow/: Airflow stack with sample DAGs and config
  - ray_certification/: Ray training, data, and serve notebooks
  - streaming_app/: Kafka/Redis/Spark streaming examples

Each subproject contains (as applicable):
- src/: Source code
- tests/: Unit tests
- pyproject.toml or requirements.txt: Environment configuration

## Usage
1. `cd projects/<subproject>`
2. Install dependencies (Poetry or pip/requirements, per project)
3. Run the entrypoint in `src/` or open the project notebooks

## Requirements
- Python 3.10+
- Poetry (https://python-poetry.org/)
- Jupyter (for notebook-based projects)

---

This repo follows Python monorepo best practices. Add new subprojects under `projects/` as needed.
