#!/usr/bin/env python

from argparse import ArgumentParser
from dataclasses import dataclass
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from datetime import datetime, timedelta, UTC, timezone
import ipaddress

import os


@dataclass
class PKIManager:
    root_folder: str

    key_size: int = 4096
    country_name: str = "FR"
    state_or_province_name: str = "Ile-De-France"
    locality_name: str = "Paris"
    organization_name: str = "Kubernetes Root CA"

    def generate_sa_key(self) -> rsa.RSAPrivateKey:
        public_path = f"{self.root_folder}/sa.pub"
        private_path = f"{self.root_folder}/sa.key"

        if os.path.exists(public_path) and os.path.exists(private_path):
            with open(private_path, "rb") as f:
                pkey = serialization.load_pem_private_key(
                    f.read(),
                    password=None,
                )
            return pkey
        os.makedirs(self.root_folder, exist_ok=True)
        pkey = rsa.generate_private_key(public_exponent=65537, key_size=self.key_size)
        with open(private_path, "wb") as f:
            f.write(
                pkey.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.TraditionalOpenSSL,
                    encryption_algorithm=serialization.NoEncryption(),
                )
            )
        with open(public_path, "wb") as f:
            f.write(
                pkey.public_key().public_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PublicFormat.SubjectPublicKeyInfo,
                )
            )
        return pkey

    def _generate_sans(self, sans: list[str]) -> x509.SubjectAlternativeName:
        san_list = []
        for san in sans:
            try:
                ip = ipaddress.ip_address(san)
                san_list.append(x509.IPAddress(ip))
            except ValueError:
                san_list.append(x509.DNSName(san))
        return x509.SubjectAlternativeName(san_list)

    def _generate_key_usages(
        self, client: bool, server: bool
    ) -> tuple[x509.KeyUsage, x509.ExtendedKeyUsage]:
        usages = {
            "content_commitment": False,
            "data_encipherment": False,
            "key_agreement": False,
            "key_cert_sign": False,
            "crl_sign": False,
            "decipher_only": False,
            "encipher_only": False,
        }
        extended_usages = []
        if server:
            usages.update(
                {
                    "digital_signature": True,
                    "key_encipherment": True,
                }
            )
            extended_usages.append(x509.ExtendedKeyUsageOID.SERVER_AUTH)
        if client:
            usages.update(
                {
                    "digital_signature": True,
                    "key_encipherment": True,
                }
            )
            extended_usages.append(x509.ExtendedKeyUsageOID.CLIENT_AUTH)
        return (x509.KeyUsage(**usages), x509.ExtendedKeyUsage(extended_usages))

    def _gen_cert(
        self,
        root_folder: str,
        cert_path: str,
        cert_key_path: str,
        country_name: str,
        state_or_province_name: str,
        locality_name: str,
        organization_name: str | None,
        common_name: str,
        ca: x509.Certificate,
        ca_key: rsa.RSAPrivateKey,
        sans: list[str] = None,
        client: bool = False,
        server: bool = False,
        days: int = 365,
        tz: timezone = UTC,
    ) -> tuple[x509.Certificate, rsa.RSAPrivateKey]:
        if os.path.exists(cert_path) and os.path.exists(cert_key_path):
            with open(cert_key_path, "rb") as f:
                pkey = serialization.load_pem_private_key(
                    f.read(),
                    password=None,
                )
            with open(cert_path, "rb") as f:
                root_certificate = x509.load_pem_x509_certificate(f.read())

            return (root_certificate, pkey)

        os.makedirs(root_folder, exist_ok=True)

        pkey = rsa.generate_private_key(public_exponent=65537, key_size=self.key_size)

        with open(cert_key_path, "wb") as f:
            f.write(
                pkey.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.TraditionalOpenSSL,
                    encryption_algorithm=serialization.NoEncryption(),
                )
            )
        subject_elements = [
            x509.NameAttribute(NameOID.COUNTRY_NAME, country_name),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, state_or_province_name),
            x509.NameAttribute(NameOID.LOCALITY_NAME, locality_name),
        ]

        if organization_name is not None:
            subject_elements.append(
                x509.NameAttribute(NameOID.ORGANIZATION_NAME, organization_name)
            )
        if common_name is not None:
            subject_elements.append(
                x509.NameAttribute(NameOID.COMMON_NAME, common_name)
            )

        subject = x509.Name(subject_elements)

        issuer = ca.subject

        usages, extended_usages = self._generate_key_usages(client, server)

        certificate = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(pkey.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.now(tz))
            .not_valid_after(datetime.now(tz) + timedelta(days=days))
            .add_extension(
                x509.BasicConstraints(ca=False, path_length=None),
                critical=True,
            )
            .add_extension(
                usages,
                critical=False,
            )
            .add_extension(
                extended_usages,
                critical=False,
            )
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(pkey.public_key()),
                critical=False,
            )
        )
        if sans is not None:
            certificate = certificate.add_extension(
                self._generate_sans(sans),
                critical=False,
            )

        if ca_key is not None:
            certificate = certificate.add_extension(
                x509.AuthorityKeyIdentifier.from_issuer_subject_key_identifier(
                    ca.extensions.get_extension_for_class(
                        x509.SubjectKeyIdentifier
                    ).value
                ),
                critical=False,
            )

        certificate = certificate.sign(
            private_key=ca_key,
            algorithm=hashes.SHA256(),
        )
        with open(cert_path, "wb") as f:
            f.write(certificate.public_bytes(encoding=serialization.Encoding.PEM))

        return (certificate, pkey)

    def _gen_ca(
        self,
        root_folder: str,
        ca_path: str,
        ca_key_path: str,
        country_name: str,
        state_or_province_name: str,
        locality_name: str,
        organization_name: str,
        common_name: str,
        parent_ca: x509.Certificate = None,
        parent_ca_key: rsa.RSAPrivateKey = None,
        days: int = 3650,
        tz: timezone = UTC,
    ) -> tuple[x509.Certificate, rsa.RSAPrivateKey]:
        assert (parent_ca is not None) == (parent_ca_key is not None), (
            "either both parent_ca and parent_ca_key must be set or none of them"
        )

        if os.path.exists(ca_path) and os.path.exists(ca_key_path):
            with open(ca_key_path, "rb") as f:
                pkey = serialization.load_pem_private_key(
                    f.read(),
                    password=None,  # set if encrypted
                )
            with open(ca_path, "rb") as f:
                root_certificate = x509.load_pem_x509_certificate(f.read())

            return (root_certificate, pkey)

        os.makedirs(root_folder, exist_ok=True)

        pkey = rsa.generate_private_key(public_exponent=65537, key_size=self.key_size)

        with open(ca_key_path, "wb") as f:
            f.write(
                pkey.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.TraditionalOpenSSL,
                    encryption_algorithm=serialization.NoEncryption(),
                )
            )

        subject = x509.Name(
            [
                x509.NameAttribute(NameOID.COUNTRY_NAME, country_name),
                x509.NameAttribute(
                    NameOID.STATE_OR_PROVINCE_NAME, state_or_province_name
                ),
                x509.NameAttribute(NameOID.LOCALITY_NAME, locality_name),
                x509.NameAttribute(NameOID.ORGANIZATION_NAME, organization_name),
                x509.NameAttribute(NameOID.COMMON_NAME, common_name),
            ]
        )

        if parent_ca is not None:
            issuer = parent_ca.subject
        else:
            issuer = subject

        certificate = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(pkey.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.now(tz))
            .not_valid_after(datetime.now(tz) + timedelta(days=days))
            .add_extension(
                x509.BasicConstraints(ca=True, path_length=None),
                critical=True,
            )
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_cert_sign=True,
                    crl_sign=True,
                    key_encipherment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    content_commitment=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=False,
            )
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(pkey.public_key()),
                critical=False,
            )
        )

        if parent_ca_key is not None:
            certificate = certificate.add_extension(
                x509.AuthorityKeyIdentifier.from_issuer_subject_key_identifier(
                    parent_ca.extensions.get_extension_for_class(
                        x509.SubjectKeyIdentifier
                    ).value,
                ),
                critical=False,
            )

        certificate = certificate.sign(
            private_key=parent_ca_key if parent_ca_key is not None else pkey,
            algorithm=hashes.SHA256(),
        )
        with open(ca_path, "wb") as f:
            f.write(certificate.public_bytes(encoding=serialization.Encoding.PEM))
        return (certificate, pkey)

    def gen_kube_etcd_cert(self, server_name: str, hosts: list[str]):
        etcd_ca_cert, etcd_ca_key = self.gen_etcd_ca()
        folder = f"{self.root_folder}/nodes/{server_name}/etcd/"
        return self._gen_cert(
            folder,
            f"{folder}/server.crt",
            f"{folder}/server.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="kube-etcd",
            ca=etcd_ca_cert,
            ca_key=etcd_ca_key,
            sans=hosts,
            server=True,
            client=True,
        )

    def gen_kube_etcd_peer_cert(self, server_name: str, hosts: list[str]):
        etcd_ca_cert, etcd_ca_key = self.gen_etcd_ca()
        folder = f"{self.root_folder}/nodes/{server_name}/etcd/"
        return self._gen_cert(
            folder,
            f"{folder}/peer.crt",
            f"{folder}/peer.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="kube-etcd-peer",
            ca=etcd_ca_cert,
            ca_key=etcd_ca_key,
            sans=hosts,
            server=True,
            client=True,
        )

    def gen_kube_etcd_peer_cert(self, server_name: str, hosts: list[str]):
        etcd_ca_cert, etcd_ca_key = self.gen_etcd_ca()
        folder = f"{self.root_folder}/nodes/{server_name}/etcd/"
        return self._gen_cert(
            folder,
            f"{folder}/peer.crt",
            f"{folder}/peer.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="kube-etcd-peer",
            ca=etcd_ca_cert,
            ca_key=etcd_ca_key,
            sans=hosts,
            server=True,
            client=True,
        )

    def gen_kube_etcd_healthcheck_cert(self, server_name: str):
        etcd_ca_cert, etcd_ca_key = self.gen_etcd_ca()
        folder = f"{self.root_folder}/nodes/{server_name}/etcd/"
        return self._gen_cert(
            folder,
            f"{folder}/healthcheck-client.crt",
            f"{folder}/healthcheck-client.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="kube-etcd-healthcheck-client",
            ca=etcd_ca_cert,
            ca_key=etcd_ca_key,
            server=False,
            client=True,
            sans=[],
        )

    def gen_kube_apiserver_etcd_cert(self, server_name: str):
        etcd_ca_cert, etcd_ca_key = self.gen_etcd_ca()
        folder = f"{self.root_folder}/nodes/{server_name}/"
        return self._gen_cert(
            folder,
            f"{folder}/apiserver-etcd-client.crt",
            f"{folder}/apiserver-etcd-client.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="kube-apiserver-etcd-client",
            ca=etcd_ca_cert,
            ca_key=etcd_ca_key,
            server=False,
            client=True,
        )

    def gen_kube_apiserver_cert(self, server_name: str, hosts: list[str]):
        ca, ca_key = self.gen_root_ca()
        folder = f"{self.root_folder}/nodes/{server_name}"
        return self._gen_cert(
            folder,
            f"{folder}/apiserver.crt",
            f"{folder}/apiserver.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="kube-apiserver",
            ca=ca,
            ca_key=ca_key,
            sans=hosts,
            server=True,
            client=False,
        )

    def gen_kube_apiserver_kubelet_cert(self, server_name: str):
        ca, ca_key = self.gen_root_ca()
        folder = f"{self.root_folder}/nodes/{server_name}"
        return self._gen_cert(
            folder,
            f"{folder}/apiserver-kubelet-client.crt",
            f"{folder}/apiserver-kubelet-client.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            organization_name="system:masters",
            common_name="kube-apiserver-kubelet-client",
            ca=ca,
            ca_key=ca_key,
            server=False,
            client=True,
        )

    def gen_front_proxy_client_cert(self, server_name: str):
        ca, ca_key = self.gen_front_proxy_ca()
        folder = f"{self.root_folder}/nodes/{server_name}"
        return self._gen_cert(
            folder,
            f"{folder}/front-proxy-client.crt",
            f"{folder}/front-proxy-client.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="front-proxy-client",
            ca=ca,
            ca_key=ca_key,
            server=False,
            client=True,
        )

    def gen_kube_proxy_cert(self, server_name: str):
        ca, ca_key = self.gen_root_ca()
        folder = f"{self.root_folder}/nodes/{server_name}"
        return self._gen_cert(
            folder,
            f"{folder}/kube-proxy.crt",
            f"{folder}/kube-proxy.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            None,
            common_name="system:kube-proxy",
            ca=ca,
            ca_key=ca_key,
            server=False,
            client=True,
        )

    def gen_root_ca(self):
        return self._gen_ca(
            self.root_folder,
            self.root_ca_path,
            self.root_ca_key_path,
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            self.organization_name,
            "Kubernetes Root CA",
        )

    def gen_etcd_ca(self):
        root_cert, root_key = self.gen_root_ca()
        return self._gen_ca(
            self.etcd_folder,
            self.etcd_ca_path,
            self.etcd_ca_key_path,
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            self.organization_name,
            parent_ca=root_cert,
            parent_ca_key=root_key,
            common_name="Kubernetes ETCD CA",
        )

    def gen_front_proxy_ca(self):
        root_cert, root_key = self.gen_root_ca()
        return self._gen_ca(
            self.root_folder,
            self.front_proxy_ca_path,
            self.front_proxy_ca_key_path,
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            self.organization_name,
            parent_ca=root_cert,
            parent_ca_key=root_key,
            common_name="Kubernetes front_proxy CA",
        )

    def gen_kubelet_cert(self, node_name: str, sans: list[str]):
        root_cert, root_key = self.gen_root_ca()
        folder = f"{self.root_folder}/nodes/{node_name}"
        self._gen_cert(
            folder,
            f"{folder}/kubelet.crt",
            f"{folder}/kubelet.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            organization_name="system:nodes",
            common_name=f"system:node:{node_name}",
            ca=root_cert,
            ca_key=root_key,
            client=True,
            sans=sans,
        )

    def gen_controller_manager_cert(self, node_name: str):
        root_cert, root_key = self.gen_root_ca()
        folder = f"{self.root_folder}/nodes/{node_name}"
        self._gen_cert(
            folder,
            f"{folder}/controller-manager.crt",
            f"{folder}/controller-manager.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            organization_name=None,
            common_name="system:kube-controller-manager",
            ca=root_cert,
            ca_key=root_key,
            client=True,
        )

    def gen_scheduler_cert(self, node_name: str):
        root_cert, root_key = self.gen_root_ca()
        folder = f"{self.root_folder}/nodes/{node_name}"
        self._gen_cert(
            folder,
            f"{folder}/scheduler.crt",
            f"{folder}/scheduler.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            organization_name=None,
            common_name="system:kube-scheduler",
            ca=root_cert,
            ca_key=root_key,
            client=True,
        )

    def gen_user_cert(self, common_name: str, organization_name: str):
        root_cert, root_key = self.gen_root_ca()
        folder = f"{self.root_folder}/users/{common_name}"
        return self._gen_cert(
            folder,
            f"{folder}/{common_name}.crt",
            f"{folder}/{common_name}.key",
            self.country_name,
            self.state_or_province_name,
            self.locality_name,
            organization_name=organization_name,
            common_name=common_name,
            ca=root_cert,
            ca_key=root_key,
            client=True,
        )

    def _generate_key_path(self, path: str) -> str:
        path = path.removesuffix(".crt")
        return f"{path}.key"

    @property
    def root_ca_path(self) -> str:
        return f"{self.root_folder}/ca.crt"

    @property
    def root_ca_key_path(self) -> str:
        return self._generate_key_path(self.root_ca_path)

    @property
    def etcd_folder(self) -> str:
        return f"{self.root_folder}/etcd"

    @property
    def etcd_ca_path(self) -> str:
        return f"{self.etcd_folder}/ca.crt"

    @property
    def etcd_ca_key_path(self) -> str:
        return self._generate_key_path(self.etcd_ca_path)

    @property
    def front_proxy_ca_path(self) -> str:
        return f"{self.root_folder}/front-proxy-ca.crt"

    @property
    def front_proxy_ca_key_path(self) -> str:
        return self._generate_key_path(self.front_proxy_ca_path)


def init_pki(pki_manager: PKIManager):
    pki_manager.gen_root_ca()
    pki_manager.gen_etcd_ca()
    pki_manager.gen_front_proxy_ca()
    pki_manager.generate_sa_key()


def generate_cert(pki_manager: PKIManager, args):
    command = args.generate_command

    all = command == "all"
    server_profile = all and not args.no_server
    client_profile = all and not args.no_worker

    if command == "kube-etcd" or all:
        pki_manager.gen_kube_etcd_cert(args.hostname, args.sans)
    if command == "kube-etcd-peer" or all:
        pki_manager.gen_kube_etcd_peer_cert(args.hostname, args.sans)
    if command == "kube-etcd-healthcheck-client" or all:
        pki_manager.gen_kube_etcd_healthcheck_cert(args.hostname)
    if command == "apiserver-etcd-client" or all:
        pki_manager.gen_kube_apiserver_etcd_cert(args.hostname)
    if command == "kube-apiserver" or all:
        pki_manager.gen_kube_apiserver_cert(args.hostname, args.sans)
    if command == "kube-apiserver-kubelet-client" or all:
        pki_manager.gen_kube_apiserver_kubelet_cert(args.hostname)
    if command == "front-proxy-client" or all:
        pki_manager.gen_front_proxy_client_cert(args.hostname)
    if command == "kube-proxy" or all:
        pki_manager.gen_kube_proxy_cert(args.hostname)
    if command == "user":
        pki_manager.gen_user_cert(args.common_name, args.group)


def bootstrap_node(pki_manager: PKIManager, args):
    node_name = args.node_name
    node_ip = args.node_ip
    pki_manager.gen_kube_etcd_cert(
        node_name, [node_ip, node_name, "localhost", "127.0.0.1"]
    )
    pki_manager.gen_kube_etcd_peer_cert(
        node_name, [node_ip, node_name, "localhost", "127.0.0.1"]
    )
    pki_manager.gen_kube_etcd_healthcheck_cert(node_name)
    pki_manager.gen_kube_apiserver_etcd_cert(node_name)
    pki_manager.gen_kube_apiserver_cert(
        node_name,
        [
            node_ip,
            node_name,
            "10.0.0.1", # TODO: add proper parameter for 'advertise IP'
            "kubernetes",
            "kubernetes.default",
            "kubernetes.default.svc",
            "kubernetes.default.svc.cluster.local",
        ],
    )
    pki_manager.gen_kube_apiserver_kubelet_cert(node_name)
    pki_manager.gen_front_proxy_client_cert(node_name)
    pki_manager.gen_kube_proxy_cert(node_name)

    pki_manager.gen_kubelet_cert(node_name, [
        node_ip,
        node_name,
    ])
    pki_manager.gen_controller_manager_cert(node_name)
    pki_manager.gen_scheduler_cert(node_name)


def _configure_cert_subparser(parent_subparsers, name: str) -> ArgumentParser:
    parser = parent_subparsers.add_parser(name, help=f"Generate a {name} certificate.")
    parser.add_argument(
        "--sans",
        type=str,
        nargs="*",
        help="Subject Alternative Names for the certificate.",
    )
    parser.add_argument("hostname", type=str, help="The hostname for the certificate.")
    return parser


def configure_bootstrap_parser(parser: ArgumentParser):
    parser.add_argument(
        "node_name", type=str, help="The name of the node to bootstrap."
    )
    parser.add_argument(
        "node_ip", type=str, help="The IP address of the node to bootstrap."
    )
    return parser


def configure_cert_parser(parser: ArgumentParser):
    subparsers = parser.add_subparsers(dest="generate_command", required=True)
    _configure_cert_subparser(subparsers, "kube-etcd")
    _configure_cert_subparser(subparsers, "kube-etcd-peer")
    _configure_cert_subparser(subparsers, "kube-etcd-healthcheck-client")
    _configure_cert_subparser(subparsers, "apiserver-etcd-client")
    _configure_cert_subparser(subparsers, "kube-apiserver")
    _configure_cert_subparser(subparsers, "kube-apiserver-kubelet-client")
    _configure_cert_subparser(subparsers, "front-proxy-client")
    _configure_cert_subparser(subparsers, "kube-proxy")
    all_parser = _configure_cert_subparser(subparsers, "all")
    all_parser.add_argument(
        "--no-server", action="store_true", help="Generate server certificates."
    )
    all_parser.add_argument(
        "--no-worker", action="store_true", help="Generate worker certificates."
    )

    user_parser = subparsers.add_parser("user", help="Generate a user certificate.")
    user_parser.add_argument(
        "common_name", type=str, help="The common name for the user certificate."
    )
    user_parser.add_argument(
        "group", type=str, help="The organization name for the user certificate."
    )

    return parser


def main():
    parser = ArgumentParser(
        description="A tool to generate certificates for kubernetes."
    )
    parser.add_argument(
        "--root-folder",
        type=str,
        required=True,
        help="The root folder to store generated certificates.",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser(
        "init", help="Initialize the PKI and generate root certificates."
    )

    generate_parser = subparsers.add_parser(
        "generate", help="Generate a certificate signed by a specified CA."
    )

    bootstrap_parser = subparsers.add_parser("bootstrap", help="Bootstrap a node.")

    configure_cert_parser(generate_parser)
    configure_bootstrap_parser(bootstrap_parser)

    args = parser.parse_args()

    pki = PKIManager(args.root_folder)

    if args.command == "init":
        init_pki(pki)
    elif args.command == "generate":
        generate_cert(pki, args)
    elif args.command == "bootstrap":
        bootstrap_node(pki, args)


if __name__ == "__main__":
    main()
