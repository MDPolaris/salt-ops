{% set mm_db_user = salt.pillar.get('micromasters:db:master_user') %}
{% set mm_db_password = salt.pillar.get('micromasters:db:master_password') %}
{% set app_user = salt.pillar.get('micromasters:db:app_user') %}
{% set app_password = salt.pillar.get('micromasters:db:app_password') %}
{% set app_db = salt.pillar.get('micromasters:db:app_db') %}
{% set db_host, db_port = salt.boto_rds.get_endpoint('micromasters-db').split(':') %}

install_postgresql_module_dependencies:
  pkg.installed:
    - name: postgresql-9.6
    - refresh: True

provision_micromasters_app_schema:
  postgres_user.present:
    - name: {{ app_user }}
    - password: {{ app_password }}
    - login: True
    - createdb: False
    - createroles: False
    - encrypted: True
    - superuser: False
    - db_host: {{ db_host }}
    - db_port: {{ db_port }}
    - db_user: {{ mm_db_user }}
    - db_password: {{ mm_db_password }}
  postgres_database.present:
    - name: {{ app_db }}
    - encoding: UTF8
    - owner: {{ app_user }}
    - owner_recurse: True
    - db_host: {{ db_host }}
    - db_port: {{ db_port }}
    - db_user: {{ mm_db_user }}
    - db_password: {{ mm_db_password }}
    - require:
        - postgres_user: provision_micromasters_app_schema
