from flask import Flask, render_template, request, redirect # web framework
import cloudinary # image hosting
import cloudinary.uploader
import boto3
from datetime import datetime
from decimal import Decimal
import sys
# Access environment variables
import os
import requests

class InstanceConfig:
    """Configuration class to avoid global variable issues"""
    _instance_id = None
    
    @classmethod
    def get_instance_id(cls):
        if cls._instance_id is None:
            try:
                # Use IMDSv2 for better security
                token_response = requests.put(
                    'http://169.254.169.254/latest/api/token',
                    headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'},
                    timeout=1
                )
                token_response.raise_for_status()
                token = token_response.text
                response = requests.get(
                    'http://169.254.169.254/latest/meta-data/instance-id',
                    headers={'X-aws-ec2-metadata-token': token},
                    timeout=1
                )
                response.raise_for_status()
                cls._instance_id = response.text
            except requests.RequestException:
                cls._instance_id = 'local-dev'
        return cls._instance_id

# Warm up the cache
InstanceConfig.get_instance_id()



# Create Flask web application instance
# Flask(__name__)
#  - Creates a new Flask application object
#  - __name__ is the name of the current Python module
#  - When run directly, __name__ equals '__main__'
#  - When imported, __name__ equals 'app'

# Why __name__ matters:
#  - Flask uses it to locate resources (templates, static files)
#  - Helps Flask find the correct directory for project files
#  - Sets the application's import name for debugging

# What app becomes:
#  - The main application object
#  - Used to register routes (@app.route)
#  - Used to configure settings (app.config)
#  - Used to run the server (app.run())

# This single line essentially initializes entire web application.
app = Flask(__name__)

# This code makes the EC2 instance ID automatically available in all Jinja2
# templates without passing it manually to each render_template call.
@app.context_processor
def inject_instance_id():
    return {'instance_id': InstanceConfig.get_instance_id()}


# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb', region_name='eu-west-2')  # Match your region
table = dynamodb.Table('BlogData')

# Helper to convert float to Decimal for DynamoDB
def float_to_decimal(obj):
    if isinstance(obj, float):
        return Decimal(str(obj))
    return obj

# Configure cloud storage for images using environment variables       
cloudinary.config( 
    cloud_name = os.environ.get("cloudinary_cloud_name"), 
    api_key = os.environ.get("cloudinary_api_key"), 
    api_secret = os.environ.get("cloudinary_api_secret"),
    secure=True
)

@app.route("/", methods=['GET'])
def index():
    try:
        response = table.scan()
        posts = response.get('Items', [])
        # Sort by PostId descending (newest first)
        posts.sort(key=lambda x: x.get('PostId', 0), reverse=True)
        return render_template("index.html", posts=posts)
    except Exception as e:
        print(f"✗ Error: {e}")
        return f"Database error: {e}", 500

@app.route("/create", methods=['GET', 'POST'])
def create():
    if request.method == 'POST':
        try:
            # Generate unique PostId (use timestamp or get max+1)
            response = table.scan(ProjectionExpression='PostId')
            existing_ids = [item['PostId'] for item in response.get('Items', [])]
            post_id = max(existing_ids, default=0) + 1
            
            title = request.form['title']
            content = request.form['content']
            
            image_url = None
            if 'image' in request.files and request.files['image'].filename:
                image = request.files['image']
                upload_result = cloudinary.uploader.upload(image)
                image_url = upload_result['secure_url']
            
            # Store in DynamoDB
            table.put_item(Item={
                'PostId': post_id,
                'title': title,
                'content': content,
                'image': image_url or '',
                'date': datetime.now().isoformat()
            })
            
            print(f"✓ Created post: {title}")
            return redirect('/')
        except Exception as e:
            print(f"✗ Error: {e}")
            return render_template("create.html", error=str(e))
    
    return render_template("create.html")


@app.route("/health")
def health():
    try:
        table.table_status
        return {"status": "healthy", "database": "connected"}, 200
    except:
        return {"status": "unhealthy"}, 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)


"""
This Flask application is a blog platform that uses DynamoDB for data storage, Cloudinary for image hosting, and runs on EC2 instances. Here's how it works:

Key Components:

1. InstanceConfig Class (Lines 12-39)

- Retrieves the EC2 instance ID using AWS Instance Metadata Service v2 (IMDSv2)

- Caches the ID to avoid repeated API calls

- Falls back to 'local-dev' if not running on EC2

- Used to display which instance is serving each request (helpful for load balancer testing)


2. DynamoDB Setup (Lines 73-74)
```
dynamodb = boto3.resource('dynamodb', region_name='eu-west-2')
table = dynamodb.Table('BlogData')
```

- Connects to your DynamoDB table in eu-west-2 region

- Uses IAM role credentials automatically (no hardcoded keys needed)

3. Cloudinary Configuration (Lines 82-87)

- Loads image hosting credentials from environment variables

- Enables secure HTTPS uploads

Routes:
/ (index) - Display all posts:

- Scans entire DynamoDB table

- Sorts posts by PostId (newest first)

- Returns all blog posts to the template





Issue: table.scan() reads the entire table, which is inefficient and expensive for large datasets. Consider pagination or using Query with a sort key.



/create - Create new post:

1. Scans table to find highest PostId

2. Generates new PostId = max + 1

3. Uploads image to Cloudinary (if provided)

4. Stores post in DynamoDB with: PostId, title, content, image URL, date

5. Redirects to homepage




Issue: The PostId generation has a race condition - if two requests happen simultaneously, they could generate the same ID. Consider using a UUID or atomic counter instead.



/health - Health check:

- Verifies DynamoDB connection by checking table status

- Used by load balancers to determine instance health


How Data Flows:
1. User submits form → Flask receives POST request

2. Image uploaded → Cloudinary returns URL

3. Data + image URL → Stored in DynamoDB

4. User redirected → Homepage scans DynamoDB → Displays all posts

Critical Dependencies:
- EC2 IAM role must have DynamoDB permissions (PutItem, Scan, GetItem)

- Environment variables must contain Cloudinary credentials

- DynamoDB table "BlogData" must exist in eu-west-2

The app runs on port 8080 and accepts connections from any network interface (required for Docker/EC2).
"""