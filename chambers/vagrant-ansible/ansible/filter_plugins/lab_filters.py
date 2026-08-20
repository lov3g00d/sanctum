"""Custom Ansible filter plugins for the vagrant-ansible chamber.

Demonstrates authoring a filter plugin. `haproxy_backends` turns the list of
web hosts into HAProxy `server` lines, looking each host's private IP up in
hostvars so the load balancer targets the isolated app network.
"""


def haproxy_backends(hosts, hostvars, port):
    lines = []
    for host in hosts:
        ip = hostvars[host]["private_ip"]
        lines.append(
            "server %s %s:%s check inter 2s fall 3 rise 2" % (host, ip, port)
        )
    return lines


class FilterModule(object):
    def filters(self):
        return {"haproxy_backends": haproxy_backends}
