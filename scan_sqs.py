import boto3
import subprocess
import time
import os
import urllib.parse
import json

AWS_REGION = os.getenv("AWS_REGION", "eu-west-2")
QUEUE_URL = os.getenv("SQS_QUEUE_URL")

# AWS Clients
sqs = boto3.client("sqs", region_name=AWS_REGION)
s3 = boto3.client("s3", region_name=AWS_REGION)

CLAMAV_DB_PATH = "/var/lib/clamav/"

def scan_file(bucket, file_key):
    """Download and scan the file with ClamAV"""
    decoded_key = urllib.parse.unquote_plus(file_key)  # Fix URL encoding issue
    print(f"🔑 Processing S3 object: {decoded_key}")
    file_path = f"/tmp/{os.path.basename(decoded_key)}"

    print(f"📥 Downloading {decoded_key} from {bucket}...")
    s3.download_file(bucket, decoded_key, file_path)

    print(f"🔍 Scanning file: {file_path}")
    result = subprocess.run(["sudo", "clamdscan", "--fdpass", file_path], capture_output=True, text=True)

    is_clean = "false" if "FOUND" in result.stdout else "true"
    print(f"🛡 Scan Result: {is_clean}")

    # Apply S3 object tag with scan result
    s3.put_object_tagging(
        Bucket=bucket,
        Key=decoded_key,
        Tagging={"TagSet": [{"Key": "is_clean", "Value": is_clean}]}
    )
    print(f"✅ Updated S3 object tags: is_clean={is_clean}")

    os.remove(file_path)

def process_sqs_messages():
    """Poll SQS for new messages and scan files"""
    while True:
        print("📡 Polling SQS for new messages...")

        response = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=10
        )

        if "Messages" not in response:
            print("❌ No new messages in SQS. Retrying...")
            continue

        message = response["Messages"][0]
        receipt_handle = message["ReceiptHandle"]

        # 🔍 Debugging: Print the full raw message
        print(f"📦 Received message: {json.dumps(message, indent=2)}")

        try:
            body = json.loads(message["Body"])

            # 🔍 Check if "Records" exists
            if "Records" not in body:
                print("⚠️ Warning: Message does not contain 'Records'. Skipping...")
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
                continue

            # 🔍 Ensure it's an S3 event
            if "s3" not in body["Records"][0]:
                print("⚠️ Warning: Message is not an S3 event. Skipping...")
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
                continue

            # 🔍 Check for "ObjectCreated" event
            event_name = body["Records"][0].get("eventName", "")
            if not event_name.startswith("ObjectCreated:"):
                print(f"⚠️ Warning: Ignoring event {event_name}. Only ObjectCreated events are processed.")
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
                continue

            bucket = body["Records"][0]["s3"]["bucket"]["name"]
            file_key = body["Records"][0]["s3"]["object"]["key"]
            print(f"🎯 Processing file: {file_key} from bucket: {bucket}")

            scan_file(bucket, file_key)

            # Delete processed message
            sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
            print(f"🗑 Deleted processed message from SQS")

        except Exception as e:
            print(f"🔥 Error processing message: {str(e)}")

if __name__ == "__main__":
    print("🚀 EC2 ClamAV Scanner is running...")
    process_sqs_messages()
