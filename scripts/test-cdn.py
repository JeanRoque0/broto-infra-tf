#!/usr/bin/env python3
"""Opt-in real AWS smoke test. Uploads one temporary object and removes its version."""
import argparse
import base64
import json
import pathlib
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def aws(*args):
    p = subprocess.run(['aws', *args, '--output', 'json'], capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError('AWS CDN smoke-test operation failed: ' + ' '.join(args[:2]))
    return json.loads(p.stdout or '{}')


def get(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, b''
    except Exception:
        raise RuntimeError('CDN HTTP request failed') from None


def signed(resource, key_id, private_key, expires):
    policy = json.dumps({'Statement': [{'Resource': resource, 'Condition': {'DateLessThan': {'AWS:EpochTime': expires}}}]}, separators=(',', ':')).encode()
    signature = subprocess.run(['openssl', 'dgst', '-sha1', '-sign', private_key], input=policy, capture_output=True, check=True).stdout
    encoded = base64.b64encode(signature).decode().translate(str.maketrans({'+': '-', '=': '_', '/': '~'}))
    return resource + '?' + urllib.parse.urlencode({'Expires': str(expires), 'Key-Pair-Id': key_id, 'Signature': encoded})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-key', required=True)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    outputs = json.loads(subprocess.check_output(['terraform', '-chdir=' + str(root / 'aws'), 'output', '-json'], text=True))
    bucket = outputs['photos_bucket']['value']
    region = outputs['github_actions_variables']['value']['AWS_REGION']
    base = outputs['photos_cdn_url']['value']
    key_id = outputs['photos_cdn_key_id']['value']
    key = 'photos/__deployment-check__/' + str(uuid.uuid4()) + '.txt'
    data = b'broto-private-cdn-smoke-test'
    version = None
    try:
        with tempfile.NamedTemporaryFile() as body:
            body.write(data)
            body.flush()
            result = aws('s3api', 'put-object', '--bucket', bucket, '--key', key, '--body', body.name,
                         '--content-type', 'text/plain', '--server-side-encryption', 'AES256', '--region', region)
            version = result.get('VersionId')
        resource = base + '/' + key
        if get(resource)[0] != 403:
            raise RuntimeError('Unsigned CDN request was not denied')
        status, received = get(signed(resource, key_id, args.private_key, int(time.time()) + 120))
        if status != 200 or received != data:
            raise RuntimeError('Valid signed CDN request did not return the uploaded object')
        if get(signed(resource, key_id, args.private_key, int(time.time()) - 60))[0] != 403:
            raise RuntimeError('Expired signed CDN URL was not denied')
        tampered = signed(resource, key_id, args.private_key, int(time.time()) + 120).replace(key, key + '-tampered')
        if get(tampered)[0] != 403:
            raise RuntimeError('Tampered signed CDN URL was not denied')
        if get('https://' + bucket + '.s3.' + region + '.amazonaws.com/' + key)[0] != 403:
            raise RuntimeError('Direct anonymous S3 access was not denied')
        print('PASS: signed read, expiry, tamper rejection, unsigned rejection and private S3 origin')
    finally:
        if version:
            aws('s3api', 'delete-object', '--bucket', bucket, '--key', key, '--version-id', version, '--region', region)
            print('Temporary S3 object version removed (edge cache expires within 300s)')


if __name__ == '__main__':
    main()
