{% set subnet_ids = [] %}
{% for subnet in salt.boto_vpc.describe_subnets(subnet_names=[
    'public1-dogwood_qa', 'public2-dogwood_qa', 'public3-dogwood_qa'])['subnets'] %}
{% do subnet_ids.append(subnet['id']) %}
{% endfor %}

generate_cloud_map_file:
  file.managed:
    - name: /etc/salt/cloud.maps.d/dogwood_qa_consul_map.yml
    - source: salt://orchestrate/aws/map_templates/consul.yml
    - template: jinja
    - makedirs: True
    - context:
        environment_name: dogwood-qa
        roles:
          - consul_server
          - service_discovery
        securitygroupid:
          - {{ salt.boto_secgroup.get_group_id(
            'consul-dogwood_qa', vpc_name='Dogwood QA') }}
          - {{ salt.boto_secgroup.get_group_id(
            'salt_master-dogwood_qa', vpc_name='Dogwood QA') }}
        subnetids: {{ subnet_ids }}

deploy_consul_nodes:
  salt.function:
    - name: saltutil.runner
    - tgt: 'roles:master'
    - tgt_type: grain
    - arg:
        - cloud.map_run
    - kwarg:
        path: /etc/salt/cloud.maps.d/dogwood_qa_consul_map.yml
        parallel: True

resize_consul_node_root_partitions:
  salt.state:
    - tgt: 'roles:consul_server'
    - tgt_type: grain
    - sls: utils.grow_partition

load_pillar_data_on_dogwood_consul_nodes:
  salt.function:
    - name: saltutil.refresh_pillar
    - tgt: 'G@roles:consul_server and G@environment:dogwood_qa'
    - tgt_type: compound

populate_mine_with_dogwood_consul_data:
  salt.function:
    - name: mine.update
    - tgt: 'G@roles:consul_server and G@environment:dogwood_qa'
    - tgt_type: compound

{# Reload the pillar data to update values from the salt mine #}
reload_pillar_data_on_dogwood_consul_nodes:
  salt.function:
    - name: saltutil.refresh_pillar
    - tgt: 'G@roles:consul_server and G@environment:dogwood_qa'
    - tgt_type: compound

build_dogwood_consul_nodes:
  salt.state:
    - tgt: 'G@roles:consul_server and G@environment:dogwood_qa'
    - tgt_type: compound
    - highstate: True
