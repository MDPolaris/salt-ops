{% set VPC_NAME = 'micromasters' %}
{% set VPC_RESOURCE_SUFFIX = VPC_NAME.lower() | replace(' ', '-') %}
{% set VPC_NET_PREFIX = '10.10' %}
{% set ENVIRONMENT = 'micromasters' %}
{% set mm_db_user = salt.pillar.get('micromasters:db:master_user') %}
{% set mm_db_password = salt.pillar.get('micromasters:db:master_password') %}

ensure_micromasters_db_subnet_group_present:
  boto_rds.subnet_group_present:
    - name: micromasters-db-subnet-group
    - subnet_names:
        - public1-{{ VPC_RESOURCE_SUFFIX }}
        - public2-{{ VPC_RESOURCE_SUFFIX }}
        - public3-{{ VPC_RESOURCE_SUFFIX }}
    - description: Subnet group for micromasters db instance

ensure_micromasters_db_parameter_group_present:
  boto_rds.parameter_present:
    - name: micromasters-db-parameters
    - db_parameter_group_family: postgres9.6
    - description: 'Parameter group for Micromasters PostGreSQL Database'
    - parameters:
        - timezone: UTC
        - client_encoding: UTF8

ensure_micromasters_postgresql_rds_db_present:
  boto_rds.present:
    - name: micromasters-db
    - allocated_storage: 100
    - db_instance_class: db.t2.medium
    - engine: postgres
    - port: {{ salt.pillar.get('micromasters:db:port') }}
    - master_username: {{ mm_db_user }}
    - master_user_password: {{ mm_db_password }}
    - db_subnet_group_name: micromasters-db-subnet-group
    - multi_az: True
    - engine_version: 9.6.1
    - auto_minor_version_upgrade: True
    - publicly_accessible: True
    - backup_retention_period: 30
    - wait_status: available
    - storage_type: gp2
    - db_parameter_group_name: micromasters-db-parameters
    - vpc_security_group_ids:
        - {{ salt.boto_secgroup.get_group_id('rds-db-{}'.format(VPC_RESOURCE_SUFFIX)) }}
