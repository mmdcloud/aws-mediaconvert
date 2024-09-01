import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as s3assets from 'aws-cdk-lib/aws-s3-assets';

export class MediaConvertStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // S3 Buckets
    const sourceBucket = new s3.Bucket(this, 'ThePlayer007MediaConvertSource', {
      bucketName: 'theplayer007-mediaconvert-source',
    });

    const destinationBucket = new s3.Bucket(this, 'ThePlayer007MediaConvertDestination', {
      bucketName: 'theplayer007-mediaconvert-destination',
    });

    // SNS Topic and Subscription
    const snsTopic = new sns.Topic(this, 'MediaConvertSnsTopic', {
      topicName: 'mediaconvert-sns-topic',
    });

    new snsSubscriptions.EmailSubscription(snsTopic.topicArn, {
      emailAddress: 'mohitfury1997@gmail.com',
    });

    // EventBridge Rule
    const rule = new events.Rule(this, 'MediaConvertEventBridgeEvent', {
      description: 'It monitors the MediaConvert job state change event',
      eventPattern: {
        source: ['aws.mediaconvert'],
        detailType: ['MediaConvert Job State Change'],
      },
    });

    // IAM Roles
    const lambdaExecutionRole = new iam.Role(this, 'MediaConvertLambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      inlinePolicies: {
        LambdaCloudwatchPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
              effect: iam.Effect.ALLOW,
            }),
          ],
        }),
        LambdaMediaConvertPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: [
                'mediaconvert:*',
                's3:ListAllMyBuckets',
                's3:ListBucket',
              ],
              resources: ['*'],
              effect: iam.Effect.ALLOW,
            }),
          ],
        }),
        PassRole: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ['iam:PassRole'],
              resources: ['*'],
              effect: iam.Effect.ALLOW,
              conditions: {
                StringLike: {
                  'iam:PassedToService': ['mediaconvert.amazonaws.com'],
                },
              },
            }),
          ],
        }),
      },
    });

    const mediaConvertS3Role = new iam.Role(this, 'MediaConvertS3Role', {
      assumedBy: new iam.ServicePrincipal('mediaconvert.amazonaws.com'),
      inlinePolicies: {
        MediaConvertS3Policy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ['s3:*', 's3-object-lambda:*'],
              resources: ['*'],
              effect: iam.Effect.ALLOW,
            }),
          ],
        }),
      },
    });

    // Lambda Function
    const lambdaFunction = new lambda.Function(this, 'MediaConvertFunction', {
      runtime: lambda.Runtime.PYTHON_3_10,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromAsset('../terraform/lambda_function.zip'),
      environment: {
        DestinationBucket: destinationBucket.bucketName,
        MediaConvertRole: mediaConvertS3Role.roleArn,
      },
      events: [
        new lambda.EventSourceMapping({
          eventSourceArn: sourceBucket.bucketArn,
          target: lambdaFunction,
          batchSize: 5,
        }),
      ],
      role: lambdaExecutionRole,
    });

    // CloudFront Distribution
    const oac = new cloudfront.CfnOriginAccessControl(this, 'MediaConvertCloudfrontOriginAccessControl', {
      originAccessControlConfig: {
        description: 'mediaconvert-s3-oac',
        name: 'mediaconvert-s3-oac',
        originAccessControlOriginType: cloudfront.OriginAccessControlOriginType.S3,
        signingBehavior: cloudfront.OriginAccessControlSigningBehavior.ALWAYS,
        signingProtocol: cloudfront.OriginAccessControlSigningProtocol.SIGV4,
      },
    });

    new cloudfront.Distribution(this, 'MediaConvertCloudfrontDistribution', {
      defaultBehavior: {
        origin: new cloudfront.origins.S3Origin(destinationBucket, {
          originAccessControl: oac,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
      },
      defaultRootObject: 'index.html',
      domainNames: ['example.com'],
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
      enabled: true,
    });
  }
}

const app = new cdk.App();
new MediaConvertStack(app, 'MediaConvertStack');
