import json
import os
import boto3
from jwt import JWT, jwk_from_dict
from jwt.utils import base64url_decode
from jwt.exceptions import JWTDecodeError, ExpiredSignatureError

client = boto3.client('cognito-idp')
USER_POOL_ID = os.environ['USER_POOL_ID']
APP_CLIENT_ID = os.environ['APP_CLIENT_ID']
REGION = os.environ['REGION']

def get_public_keys():
    """Get public keys from Cognito to verify JWT tokens"""
    jwks_url = f'https://cognito-idp.{REGION}.amazonaws.com/{USER_POOL_ID}/.well-known/jwks.json'
    jwks = requests.get(jwks_url).json()
    return {key['kid']: jwk_from_dict(key) for key in jwks['keys']}

def verify_token(token):
    """Verify Cognito JWT token"""
    try:
        headers = JWT().get_unverified_headers(token)
        kid = headers['kid']
        public_keys = get_public_keys()
        public_key = public_keys[kid]
        
        claims = JWT().decode(
            token,
            key=public_key,
            algorithms=['RS256'],
            audience=APP_CLIENT_ID,
            issuer=f'https://cognito-idp.{REGION}.amazonaws.com/{USER_POOL_ID}'
        )
        return claims
    except (JWTDecodeError, ExpiredSignatureError, KeyError) as e:
        print(f"Token verification failed: {str(e)}")
        return None

def lambda_handler(event, context):
    print("Received event: " + json.dumps(event))
    
    # Extract token from headers
    auth_header = event.get('headers', {}).get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return generate_policy('user', 'Deny', event['methodArn'])
    
    token = auth_header.split(' ')[1]
    claims = verify_token(token)
    
    if not claims:
        return generate_policy('user', 'Deny', event['methodArn'])
    
    # Token is valid - allow access
    return generate_policy(claims['sub'], 'Allow', event['methodArn'], claims)

def generate_policy(principal_id, effect, resource, context=None):
    """Generate IAM policy for API Gateway"""
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [{
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': resource
            }]
        }
    }
    
    if context:
        policy['context'] = context
    
    return policy