# Make sure that instance profiles exist for node types so that
# they can be granted access via permissions attached to those
# profiles because it's easier than managing IAM keys
{% for profile in ['consul', 'mongodb', 'rabbitmq', 'edx'] %}
ensure_instance_profile_exists_for_{{ profile }}:
  boto_iam_role.present:
    - name: {{ profile }}-instance-role
{% endfor %}

{% set VPC_NAME = 'MITx RP' %}

create_mitx-rp_vpc:
  boto_vpc.present:
    - name: {{ VPC_NAME }}
    - cidr_block: 10.6.0.0/16
    - instance_tenancy: default
    - dns_support: True
    - dns_hostnames: True
    - tags:
        Name: {{ VPC_NAME }}

create_mitx-rp_internet_gateway:
  boto_vpc.internet_gateway_present:
    - name: mitx-rp-igw
    - vpc_name: {{ VPC_NAME }}
    - require:
        - boto_vpc: create_mitx-rp_vpc
    - tags:
        Name: mitx-rp-igw

create_mitx-rp_public_subnet_1:
  boto_vpc.subnet_present:
    - name: public1-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - cidr_block: 10.6.1.0/24
    - availability_zone: us-east-1d
    - require:
        - boto_vpc: create_mitx-rp_vpc
    - tags:
        Name: public1-mitx-rp

create_mitx-rp_public_subnet_2:
  boto_vpc.subnet_present:
    - name: public2-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - cidr_block: 10.6.2.0/24
    - availability_zone: us-east-1b
    - require:
        - boto_vpc: create_mitx-rp_vpc
    - tags:
        Name: public2-mitx-rp

create_mitx-rp_public_subnet_3:
  boto_vpc.subnet_present:
    - name: public3-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - cidr_block: 10.6.3.0/24
    - availability_zone: us-east-1c
    - require:
        - boto_vpc: create_mitx-rp_vpc
    - tags:
        Name: public3-mitx-rp

create_mitx_private_db_subnet:
  boto_vpc.subnet_present:
    - name: private_db_subnet-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - cidr_block: 10.6.5.0/24
    - require:
        - boto_vpc: create_mitx-rp_vpc
    - tags:
        Name: private_db_subnet-mitx-rp

create_mitx_rp_vpc_peering_connection_with_operations:
  boto_vpc.vpc_peering_connection_present:
    - conn_name: mitx-rp-operations-peer
    - requester_vpc_name: MITx RP
    - peer_vpc_name: mitodl-operations-services

accept_mitx_rp_vpc_peering_connection_with_operations:
  boto_vpc.accept_vpc_peering_connection:
    - conn_name: mitx-rp-operations-peer

create_mitx-rp_routing_table:
  boto_vpc.route_table_present:
    - name: mitx-rp-route_table
    - vpc_name: {{ VPC_NAME }}
    - subnet_names:
        - public1-mitx-rp
        - public2-mitx-rp
        - public3-mitx-rp
        - private_db_subnet-mitx-rp
    - routes:
        - destination_cidr_block: 0.0.0.0/0
          internet_gateway_name: mitx-rp-igw
        - destination_cidr_block: 10.0.0.0/22
          vpc_peering_connection_name: mitx-rp-operations-peer
    - require:
        - boto_vpc: create_mitx-rp_vpc
        - boto_vpc: create_mitx-rp_public_subnet_1
        - boto_vpc: create_mitx-rp_public_subnet_2
        - boto_vpc: create_mitx-rp_public_subnet_3
        - boto_vpc: create_mitx_rp_vpc_peering_connection_with_operations
    - tags:
        Name: mitx-rp-route_table

create_edx_security_group:
  boto_secgroup.present:
    - name: edx-mitx-rp
    - description: Access rules for EdX instances
    - vpc_name: {{ VPC_NAME }}
    - rules:
        - ip_protocol: tcp
          from_port: 80
          to_port: 80
          cidr_ip: 0.0.0.0/0
        - ip_protocol: tcp
          from_port: 443
          to_port: 443
          cidr_ip: 0.0.0.0/0
        - ip_protocol: tcp
          from_port: 22
          to_port: 22
          cidr_ip:
            - 10.0.0.0/22
            - 10.6.0.0/22
        - ip_protocol: tcp
          from_port: 18040
          to_port: 18040
          cidr_ip: 10.6.0.0/22
    - require:
        - boto_vpc: create_mitx-rp_vpc
    - tags:
        Name: edx-mitx-rp

create_mongodb_security_group:
  boto_secgroup.present:
    - name: mongodb-mitx-rp
    - description: Grant access to Mongo from EdX instances
    - vpc_name: {{ VPC_NAME }}
    - rules:
        - ip_protocol: tcp
          from_port: 27017
          to_port: 27017
          source_group_name:
            - edx-mitx-rp
            - mongodb-mitx-rp
        - ip_protocol: tcp
          from_port: 22
          to_port: 22
          cidr_ip:
            - 10.0.0.0/22
            - 10.6.0.0/22
    - require:
        - boto_vpc: create_mitx-rp_vpc
        - boto_secgroup: create_edx_security_group
    - tags:
        Name: mongodb-mitx-rp

create_mitx_consul_security_group:
  boto_secgroup.present:
    - name: consul-mitx-rp
    - description: Access rules for Consul cluster in {{ VPC_NAME }} stack
    - vpc_name: {{ VPC_NAME }}
    - rules:
        - ip_protocol: tcp
          from_port: 8500
          to_port: 8500
          cidr_ip:
            - 10.6.0.0/22
          {# HTTP access #}
        - ip_protocol: udp
          from_port: 8500
          to_port: 8500
          cidr_ip:
            - 10.6.0.0/22
          {# HTTP access #}
        - ip_protocol: tcp
          from_port: 8600
          to_port: 8600
          cidr_ip:
            - 10.6.0.0/22
          {# DNS access #}
        - ip_protocol: udp
          from_port: 8600
          to_port: 8600
          cidr_ip:
            - 10.6.0.0/22
          {# DNS access #}
        - ip_protocol: tcp
          from_port: 8300
          to_port: 8301
          cidr_ip:
            - 10.6.0.0/22
          {# LAN gossip protocol #}
        - ip_protocol: udp
          from_port: 8300
          to_port: 8301
          cidr_ip:
            - 10.6.0.0/22
          {# LAN gossip protocol #}
        - ip_protocol: tcp
          from_port: 8300
          to_port: 8302
          cidr_ip:
            - 10.0.0.0/22
            - 10.6.0.0/22
          {# WAN cluster interface #}
    - require:
        - boto_vpc: create_mitx-rp_vpc
    - tags:
        Name: consul-mitx-rp

create_mitx_consul_agent_security_group:
  boto_secgroup.present:
    - name: consul-agent-mitx-rp
    - description: Access rules for Consul agent in {{ VPC_NAME }} stack
    - vpc_name: {{ VPC_NAME }}
    - rules:
        - ip_protocol: tcp
          from_port: 8301
          to_port: 8301
          source_group_name: consul-agent-mitx-rp
        - ip_protocol: udp
          from_port: 8301
          to_port: 8301
          source_group_name: consul-agent-mitx-rp
          - ip_protocol: tcp
          from_port: 8301
          to_port: 8301
          source_group_name: consul-mitx-rp
        - ip_protocol: udp
          from_port: 8301
          to_port: 8301
          source_group_name: consul-mitx-rp
    - require:
        - boto_vpc: create_mitx_rp_vpc
        - boto_secgroup: create_mitx_consul_security_group
    - tags:
        Name: consul-agent-mitx-rp

create_rabbitmq_security_group:
  boto_secgroup.present:
    - name: rabbitmq-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - description: ACL for RabbitMQ servers
    - rules:
        - ip_protocol: tcp
          from_port: 5672
          to_port: 5672
          source_group_name: edx-mitx-rp
        - ip_protocol: tcp
          from_port: 4369
          to_port: 4369
          source_group_name: rabbitmq-mitx-rp
        - ip_protocol: tcp
          from_port: 25672
          to_port: 25672
          source_group_name: rabbitmq-mitx-rp
    - require:
        - boto_vpc: create_mitx-rp_vpc
        - boto_secgroup: create_edx_security_group
    - tags:
        Name: rabbitmq-mitx-rp

create_elasticsearch_security_group:
  boto_secgroup.present:
    - name: elasticsearch-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - description: ACL for elasticsearch servers
    - rules:
        - ip_protocol: tcp
          from_port: 9200
          to_port: 9200
          source_group_name: edx-mitx-rp
        - ip_protocol: tcp
          from_port: 9300
          to_port: 9400
          source_group_name: elasticsearch-mitx-rp
    - require:
        - boto_vpc: create_mitx-rp_vpc
        - boto_secgroup: create_edx_security_group
    - tags:
        Name: elasticsearch-mitx-rp

create_rds_security_group:
  boto_secgroup.present:
    - name: rds-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - description: ACL for RDS access
    - rules:
        - ip_protocol: tcp
          from_port: 3306
          to_port: 3306
          source_group_name: edx-mitx-rp
        - ip_protocol: tcp
          from_port: 3306
          to_port: 3306
          source_group_name: consul-mitx-rp
    - require:
        - boto_vpc: create_mitx-rp_vpc
        - boto_secgroup: create_edx_security_group
    - tags:
        Name: rds-mitx-rp

create_salt_master_security_group:
  boto_secgroup.present:
    - name: salt_master-mitx-rp
    - vpc_name: {{ VPC_NAME }}
    - description: ACL for allowing access to hosts from Salt Master
    - tags:
        Name: salt_master-mitx-rp
    - rules:
        - ip_protocol: tcp
          from_port: 22
          to_port: 22
          cidr_ip:
            - 10.0.0.0/22
    - require:
        - boto_vpc: create_mitx-rp_vpc
