import os
import boto3
ec2 = boto3.client('ec2')

# Supplied by the stack's parameters.  The fallbacks keep the
# handler runnable on its own, and match the parameter defaults.
PROJECT_TAG_KEY = os.environ.get('PROJECT_TAG_KEY', 'project')
ENVIRONMENT_TAG_KEY = os.environ.get('ENVIRONMENT_TAG_KEY', 'environment')
NAME_FORMAT = os.environ.get('NAME_FORMAT', '{project}-{environment}-{instance_id}')

class LambdaException(Exception):
  pass

def verify_instance_exists(instance_id):
  result = ec2.describe_instance_status(InstanceIds=[instance_id], IncludeAllInstances=True)
  if 'InstanceStatuses' not in result:
    raise LambdaException("Result payload spec changed, aborting. Payload: {}".format(result))
  elif len(result['InstanceStatuses']) < 1:
    raise LambdaException("Instance not found: {}".format(instance_id))
  elif len(result['InstanceStatuses']) > 1:
    raise LambdaException("1+ instances found for instance {}.  Aborting to prevent damage".format(instance_id))

def get_tags(instance_id):
  result = ec2.describe_tags(
    Filters=[{'Name': 'resource-id', 'Values': [instance_id]}])
  if 'Tags' not in result:
    raise LambdaException("Result payload spec changed, aborting. Payload: {}".format(result))
  return result['Tags']

def assert_name_tag_not_set(instance_id, tag_list):
  tag = [i for i in tag_list if i['Key'] == 'Name' if i['Value'] != '']
  if len(tag):
    val = tag[0]['Value']
    raise LambdaException("Name tag already set to {} on instance {}".format(val, instance_id))

def get_tag_value(tag_list, key):
  tag = [i for i in tag_list if i['Key'] == key if i['Value'] != '']
  if not tag:
    raise LambdaException("Tag {} not found in list {}".format(key, tag_list))
  return tag[0]['Value']

def build_name(project, env, instance_id):
  id = instance_id.split('-')[1]  # strip the i-
  try:
    name = NAME_FORMAT.format(project=project, environment=env, instance_id=id)
  except (KeyError, IndexError) as e:
    raise LambdaException(
      "NAME_FORMAT {} uses an unknown placeholder {}.  Valid placeholders are "
      "project, environment and instance_id".format(NAME_FORMAT, e))
  return name[:255]   # tag values max out at 255 chars

def name_instance(instance_id, name):
  tag = dict()
  tag['Key'] = 'Name'
  tag['Value'] = name

  result = ec2.create_tags(Resources=[instance_id], Tags=[tag])

  if result['ResponseMetadata']['HTTPStatusCode'] != 200:
    raise LambdaException("Tag creation failed.  Response: {}".format(result))
  else:
    print("SUCCESS: Tagging {} with name {}".format(instance_id, name))

def lambda_handler(event, context):
  instance_id = event['detail']['EC2InstanceId']

  try:
    verify_instance_exists(instance_id)
    tag_list = get_tags(instance_id)

    assert_name_tag_not_set(instance_id, tag_list)

    project_tag = get_tag_value(tag_list, PROJECT_TAG_KEY)
    env_tag = get_tag_value(tag_list, ENVIRONMENT_TAG_KEY)

    name = build_name(project_tag, env_tag, instance_id)
    name_instance(instance_id, name)
  except LambdaException as e:
    print("ERROR: {}".format(e.args[0]))
