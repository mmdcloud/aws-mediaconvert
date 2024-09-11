import * as cdk from 'aws-cdk';
import { Stack, StackProps } from 'aws-cdk';
import { Bucket, BucketPolicy } from 'aws-cdk/aws-s3';
import { Table, AttributeType, BillingMode } from 'aws-cdk/aws-dynamodb';
import { Topic, Subscription } from 'aws-cdk/aws-sns';
import { SnsSubscription } from 'aws-cdk/aws-sns-subscriptions';
import { Role, ServicePrincipal, PolicyStatement } from 'aws-cdk/aws-iam';
import { Function, Runtime, Code } from 'aws-cdk/aws-lambda';
import { Rule, EventPattern } from 'aws-cdk/aws-events';
import { SnsEventSource } from 'aws-cdk/aws-lambda-event-sources';
import { CloudFrontWebDistribution, OriginAccessIdentity, CloudFrontAllowedMethods, CloudFrontAllowedHeaders } from 'aws-cdk/aws-cloudfront';

export class MediaConvertStack extends Stack {
  constructor(scope: cdk.Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // S3 Buckets
    const sourceBucket = new Bucket(this, 'ThePlayer007MediaConvertSource', {
      bucketName: 'theplayer007-mediaconvert-source',
    });

    const destinationBucket = new Bucket(this, 'ThePlayer007MediaConvertDestination', {
      bucketName: 'theplayer007-mediaconvert-destination',
    });

    // DynamoDB Table
    const table = new Table(this, 'DynamoDBTable', {
      tableName: 'MediaconvertRecords',
      partitionKey: { name: 'RecordId', type: AttributeType.STRING },
      sortKey: { name: 'Timestamp', type: AttributeType.NUMBER },
      billingMode: BillingMode.PROVISIONED,
      readCapacity: 20,
      writeCapacity: 20,
    });

    // SNS Topic
    const snsTopic = new Topic(this, 'MediaConvertSnsTopic', {
      topicName: 'mediaconvert-sns-topic',
    });

    // SNS Subscription
    // snsTopic.addSubscription(new SnsSubscription({
    //   endpoint: 'mohitfury1997@gmail.com',
    //   protocol: sns.SubscriptionProtocol.EMAIL,
    // }));

    // IAM Roles
    const lambdaExecutionRole = new Role(this, 'MediaConvertLambdaExecutionRole', {
      assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
    });

    lambdaExecutionRole.addToPolicy(new PolicyStatement({
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: ['*'],
    }));

    lambdaExecutionRole.addToPolicy(new PolicyStatement({
      actions: [
        'mediaconvert:*',
        's3:ListAllMyBuckets',
        's3:ListBucket',
      ],
      resources: ['*'],
    }));

    lambdaExecutionRole.addToPolicy(new PolicyStatement({
      actions: ['iam:PassRole'],
      resources: ['*'],
      conditions: {
        StringLike: {
          'iam:PassedToService': ['mediaconvert.amazonaws.com'],
        },
      },
    }));

    const mediaConvertS3Role = new Role(this, 'MediaConvertS3Role', {
      assumedBy: new ServicePrincipal('mediaconvert.amazonaws.com'),
    });

    mediaConvertS3Role.addToPolicy(new PolicyStatement({
      actions: [
        's3:*',
        's3-object-lambda:*',
      ],
      resources: ['*'],
    }));

    // Lambda Function
    const lambdaFunction = new Function(this, 'MediaConvertFunction', {
      handler: 'lambda_function.lambda_handler',
      runtime: Runtime.PYTHON_3_10,
      code: Code.fromAsset('path/to/lambda_function.zip'),
      environment: {
        DestinationBucket: destinationBucket.bucketName,
        MediaConvertRole: mediaConvertS3Role.roleArn,
      },
    });

    sourceBucket.grantRead(lambdaFunction);

    // EventBridge Rule
    new Rule(this, 'MediaConvertEventBridgeEvent', {
      description: 'It monitors the media convert job state change event',
      eventPattern: {
        source: ['aws.mediaconvert'],
        detailType: ['MediaConvert Job State Change'],
      },
      targets: [new SnsEventSource(snsTopic)],
    });

    // // CloudFront Origin Access Control
    // const oac = new OriginAccessIdentity(this, 'MediaConvertCloudfrontOriginAccessControl', {
    //   comment: 'mediaconvert-s3-oac',
    // });

    // // CloudFront Distribution
    // new CloudFrontWebDistribution(this, 'MediaConvertCloudfrontDistribution', {
    //   originConfigs: [{
    //     s3OriginSource: {
    //       s3BucketSource: destinationBucket,
    //       originAccessIdentity: oac,
    //     },
    //     behaviors: [{
    //       isDefaultBehavior: true,
    //       allowedMethods: CloudFrontAllowedMethods.GET_HEAD,
    //       allowedHeaders: CloudFrontAllowedHeaders.NONE,
    //       compress: true,
    //       defaultTtl: cdk.Duration.seconds(0),
    //       minTtl: cdk.Duration.seconds(0),
    //       maxTtl: cdk.Duration.seconds(0),
    //     }],
    //   }],
    //   viewerCertificate: {
    //     cloudFrontDefaultCertificate: true,
    //   },
    //   defaultRootObject: 'index.html',
    //   priceClass: 'PriceClass_200',
    // });

    // // Bucket Policy for CloudFront
    // new BucketPolicy(this, 'MediaConvertDestinationBucketPolicy', {
    //   bucket: destinationBucket,
    //   policyDocument: {
    //     version: '2012-10-17',
    //     statements: [{
    //       actions: ['s3:GetObject'],
    //       resources: [`${destinationBucket.bucketArn}/*`],
    //       effect: 'Allow',
    //       principals: [new ServicePrincipal('cloudfront.amazonaws.com')],
    //       conditions: {
    //         StringEquals: {
    //           'AWS:SourceArn': `arn:aws:cloudfront::${cdk.Aws.ACCOUNT_ID}:distribution/${distribution.distributionId}`,
    //         },
    //       },
    //     }],
    //   },
    // });
  }
}

const app = new cdk.App();
new MediaConvertStack(app, 'MediaConvertStack');