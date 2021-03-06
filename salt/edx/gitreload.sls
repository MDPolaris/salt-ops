{% set gr_dir = salt.pillar.get('edx:gitreload:gr_dir', '/edx/app/gitreload') -%}
{% set gr_env = salt.pillar.get('edx:gitreload:gr_env', {
    'PORT': 8095,
    'UPDATE_LMS': True,
    'REPODIR': '/mnt/data/repos',
    'LOG_LEVEL': 'debug',
    'NUM_THREADS': 1,
    'LOGFILE': "/edx/var/log/gr/gitreload.log",
    'VIRTUAL_ENV': '/edx/app/edxapp/venvs/edxapp',
    'EDX_PLATFORM': '/edx/app/edxapp/edx-platform',
    'DJANGO_SETTINGS': 'aws'
}) -%}
{% set gr_repo = salt.pillar.get('edx:gitreload:gr_repo',
                                 'github.com/mitodl/gitreload') -%}
{% set gr_repos = salt.pillar.get('edx:gitreload:gr_repos', []) -%}
{% set gr_version = salt.pillar.get('edx:gitreload:gr_version',
                                    'ba53a4b0e0618891535aa9107c3d113227540e39') -%}
{% set ssh_hosts = salt.pillar.get('edx:ssh_hosts',
   [{'name': 'github.com', 'fingerprint': '16:27:ac:a5:76:28:2d:36:63:1b:56:4d:eb:df:a6:48'},
    {'name': 'github.mit.edu', 'fingerprint': '03:3b:72:d6:20:6f:3e:1f:5e:2f:38:a2:80:01:f3:22'}]) %}
{% set gr_log_dir = salt.pillar.get('edx:gitreload:gr_log_dir',
                                  '/edx/var/log/gr') -%}
{% set hostname = salt.pillar.get('edx:gitreload:hostname') -%}
{% set basic_auth = salt.pillar.get('edx:gitreload:basic_auth', {
  'username': 'mitx',
  'password': 'change_me',
  'location': '/edx/app/nginx/gitreload.htpasswd'
}) -%}

install_mit_github_ssh_key:
  file.managed:
    - name: /var/www/.ssh/id_rsa
    - user: www-data
    - group: www-data
    - contents_pillar: 'edx:ssh_key'
    - makedirs: True
    - mode: 0600
    - dir_mode: 0700

{% for host in ssh_hosts %}
add_{{ host.name }}_to_known_hosts_for_gitreload:
  ssh_known_hosts.present:
    - name: {{ host.name }}
    - user: www-data
    - fingerprint: {{ host.fingerprint }}
    - require:
      - file: install_mit_github_ssh_key
{% endfor %}

create_gitreload_config:
  file.managed:
    - name: {{ gr_dir }}/gr.env.json
    - source: salt://edx/templates/gitreload_config.json.j2
    - owner: www-data
    - group: www-data
    - template: jinja
    - context:
        gr_env: {{ gr_env }}
    - makedirs: True

install_gitreload:
  pip.installed:
    - name: git+https://{{ gr_repo }}@{{ gr_version }}#egg=gitreload-latest
    - exists_action: w
    - bin_env: {{ gr_env.VIRTUAL_ENV }}
    - upgrade: True
    - user: edxapp

{% for path in [gr_dir, gr_log_dir, gr_env.REPODIR] %}
create_{{ path }}_directories:
  file.directory:
    - name: {{ path }}
    - user: www-data
    - group: www-data
    - makedirs: True
    - require_in:
      - file: gitreload_init_script
{% endfor %}

{% for item in gr_repos %}
pull_{{ item.name }}_repo:
  git.latest:
    - name: {{ item.url }}
    - target: {{ gr_env.REPODIR }}/{{ item.name }}
    - rev: {{ item.commit }}
    - user: www-data
    - require:
      {% for host in ssh_hosts %}
      - cmd: save_{{ host }}_ssh_host_key
      {% endfor %}

import_{{ item.name }}_course:
  cmd.script:
    - source: salt://edx/templates/gitreload_import.sh.j2
    - template: jinja
    - context:
        gr_env: {{ gr_env }}
        item: {{ item }}
    - require:
      - git: pull_{{ item.name }}_repo
{% endfor %}

gitreload_init_script:
  file.managed:
    - name: /etc/init/gitreload.conf
    - source: salt://edx/templates/gitreload_init.conf.j2
    - template: jinja
    - mode: 644
    - context:
        gr_env: {{ gr_env }}
        gr_dir: {{ gr_dir }}

gitreload_htpasswd:
  file.managed:
    - name: {{ basic_auth.location }}
    - contents: {{ basic_auth.username }}:{{ salt['cmd.run']('openssl passwd -quiet -crypt {}'.format(basic_auth.password)) }}
    - user: www-data
    - group: www-data

gitreload_site:
  file.managed:
    - name: /edx/app/nginx/sites-available/gitreload
    - source: salt://edx/templates/gitreload_site.j2
    - template: jinja
    - mode: 640
    - makedirs: True
    - user: root
    - group: www-data
    - context:
        gr_env: {{ gr_env }}
        hostname: {{ hostname }}
        htpasswd: {{ basic_auth.location }}
    - require:
      - file: gitreload_htpasswd

enable_gitreload_link:
  file.symlink:
    - name: /etc/nginx/sites-enabled/gitreload
    - target: /edx/app/nginx/sites-available/gitreload
    - user: root
    - group: root
    - require:
      - file: gitreload_site

reload_nginx:
  service.running:
    - name: nginx
    - reload: True
    - watch:
      - file: enable_gitreload_link
      - file: gitreload_htpasswd
      - file: gitreload_site

start_gitreload:
  service.running:
    - name: gitreload
    - enable: True
    - require:
      - file: gitreload_init_script
      - file: create_gitreload_config
