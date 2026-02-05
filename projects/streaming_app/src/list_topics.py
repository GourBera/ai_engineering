import os
import subprocess
import shlex
from kafka.admin import KafkaAdminClient


def detect_bootstrap_from_kubectl():
    """Try to detect Strimzi/Cluster bootstrap address via kubectl.
    Returns a list of bootstrap addresses or None if not found.
    """
    try:
        cmd = [
            "kubectl",
            "get",
            "kafka",
            "-n",
            "kafka",
            "-o",
            'jsonpath={.items[0].status.listeners[?(@.name=="external")].bootstrapServers}'
        ]
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True).strip()
        if out:
            return [s.strip() for s in out.split(",") if s.strip()]
    except Exception:
        pass
    return None


def get_bootstrap_servers():
    # load project .env if present (written by startup/startup.sh)
    try:
        here = os.path.dirname(__file__)
        project_root = os.path.normpath(os.path.join(here, ".."))
        env_path = os.path.join(project_root, ".env")
        if os.path.exists(env_path):
            with open(env_path, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" in line:
                        k, v = line.split("=", 1)
                        k = k.strip()
                        v = v.strip().strip('"').strip("'")
                        os.environ.setdefault(k, v)
    except Exception:
        pass

    # environment override (comma separated)
    env = os.getenv("KAFKA_BOOTSTRAP_SERVERS") or os.getenv("BOOTSTRAP_SERVERS")
    if env:
        return [s.strip() for s in env.split(",") if s.strip()]

    detected = detect_bootstrap_from_kubectl()
    if detected:
        return detected

    # fallback to localhost:9092 (startup script will port-forward)
    return ["127.0.0.1:9092"]


def list_topics(bootstrap_servers):
    print("Using bootstrap servers:", bootstrap_servers)
    # initial attempt
    admin = None
    try:
        admin = KafkaAdminClient(bootstrap_servers=bootstrap_servers, client_id="topic_lister")
        topics = admin.list_topics()
        print("Topics in Kafka cluster:")
        for t in sorted(topics):
            print(" -", t)
        return
    except Exception as e:
        print("Initial attempt to list topics failed:", e)
    finally:
        if admin:
            try:
                admin.close()
            except Exception:
                pass

    # Fallback: try to port-forward the broker pod directly and retry once
    try:
        print("Attempting to port-forward the broker pod and retry...")
        pod_name = None
        try:
            pods_out = subprocess.check_output(["kubectl", "get", "pods", "-n", "kafka", "-o", "jsonpath={.items[*].metadata.name}"], text=True)
            for p in pods_out.split():
                if p.startswith("my-kafka-") and p.endswith("-0"):
                    pod_name = p
                    break
            if not pod_name and pods_out.split():
                pod_name = pods_out.split()[0]
        except Exception:
            pod_name = None

        pf_proc = None
        if pod_name:
            print(f"Port-forwarding pod {pod_name} -> localhost:9092")
            pf_proc = subprocess.Popen(["kubectl", "port-forward", "-n", "kafka", f"pod/{pod_name}", "9092:9092"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # wait for port to open
            for _ in range(30):
                try:
                    if subprocess.call(["nc", "-z", "127.0.0.1", "9092"]) == 0:
                        break
                except Exception:
                    pass
                time.sleep(1)

        # retry
        admin = None
        try:
            admin = KafkaAdminClient(bootstrap_servers=["127.0.0.1:9092"], client_id="topic_lister")
            topics = admin.list_topics()
            print("Topics in Kafka cluster (after pod port-forward):")
            for t in sorted(topics):
                print(" -", t)
            return
        except Exception as e:
            print("Retry after port-forward failed:", e)
        finally:
            if admin:
                try:
                    admin.close()
                except Exception:
                    pass
            if pf_proc:
                try:
                    pf_proc.send_signal(signal.SIGTERM)
                    pf_proc.wait(timeout=5)
                except Exception:
                    try:
                        pf_proc.kill()
                    except Exception:
                        pass
        # Final fallback: exec into the broker pod and run kafka-topics.sh there
        try:
            if pod_name:
                print(f"Attempting kubectl exec into pod {pod_name} to list topics")
                cmd_candidates = [
                    ["kubectl", "exec", "-n", "kafka", pod_name, "--", "kafka-topics.sh", "--bootstrap-server", "localhost:9092", "--list"],
                    ["kubectl", "exec", "-n", "kafka", pod_name, "--", "/opt/kafka/bin/kafka-topics.sh", "--bootstrap-server", "localhost:9092", "--list"]
                ]
                out = None
                for cmd in cmd_candidates:
                    try:
                        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
                        break
                    except subprocess.CalledProcessError:
                        out = None
                if out is not None:
                    lines = [l.strip() for l in out.splitlines() if l.strip()]
                    if lines:
                        print("Topics (via kubectl exec):")
                        for l in lines:
                            print(" -", l)
                        return
        except Exception as e:
            print("kubectl exec fallback failed:", e)
    except Exception as e:
        print("Fallback port-forward attempt failed:", e)


if __name__ == "__main__":
    servers = get_bootstrap_servers()
    list_topics(servers)
