import os
import base64
import json
import shutil
from io import BytesIO
from flask import Flask, render_template, request, redirect, url_for, flash
from werkzeug.utils import secure_filename
import boto3
from PIL import Image
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY', 'default-secret-key')

# Configure upload folder
UPLOAD_FOLDER = 'uploads'
STATIC_UPLOAD_FOLDER = 'static/uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# Create uploads directory if it doesn't exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(STATIC_UPLOAD_FOLDER, exist_ok=True)

# Initialize Bedrock client
bedrock_runtime = boto3.client(
    service_name='bedrock-runtime',
    region_name=os.getenv('AWS_REGION', 'us-east-1')
)

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')

def extract_text_from_image(image_path):
    # Encode image to base64
    base64_image = encode_image(image_path)
    
    # Prepare the request payload for Claude 3
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1000,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "Extract all text from this image. Return only the extracted text, nothing else."
                    },
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64_image
                        }
                    }
                ]
            }
        ]
    }
    
    # Call Claude 3 Sonnet model
    response = bedrock_runtime.invoke_model(
        modelId="anthropic.claude-3-sonnet-20240229-v1:0",
        body=json.dumps(payload)
    )
    
    response_body = json.loads(response['body'].read())
    extracted_text = response_body['content'][0]['text']
    
    return extracted_text

def translate_text(text, target_language='th'):
    # Prepare the request payload for Claude 3
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1000,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Translate the following text to Thai language. Return only the translated text, nothing else:\n\n{text}"
                    }
                ]
            }
        ]
    }
    
    # Call Claude 3 Sonnet model
    response = bedrock_runtime.invoke_model(
        modelId="anthropic.claude-3-sonnet-20240229-v1:0",
        body=json.dumps(payload)
    )
    
    response_body = json.loads(response['body'].read())
    translated_text = response_body['content'][0]['text']
    
    return translated_text

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        # Check if the post request has the file part
        if 'file' not in request.files:
            flash('No file part')
            return redirect(request.url)
        
        file = request.files['file']
        
        # If user does not select file, browser also
        # submit an empty part without filename
        if file.filename == '':
            flash('No selected file')
            return redirect(request.url)
        
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(filepath)
            
            # Copy the file to static folder for display
            static_filepath = os.path.join(STATIC_UPLOAD_FOLDER, filename)
            shutil.copy2(filepath, static_filepath)
            
            try:
                # Extract text from image
                extracted_text = extract_text_from_image(filepath)
                
                # Translate text to Thai
                translated_text = translate_text(extracted_text)
                
                return render_template('result.html', 
                                      image_path=filepath,
                                      original_text=extracted_text,
                                      translated_text=translated_text)
            except Exception as e:
                flash(f'Error processing image: {str(e)}')
                return redirect(request.url)
        else:
            flash('Allowed file types are png, jpg, jpeg')
            return redirect(request.url)
    
    return render_template('index.html')

if __name__ == '__main__':
    # For local development
    app.run(debug=os.getenv('FLASK_DEBUG', 'False') == 'True', 
            host='0.0.0.0', 
            port=int(os.getenv('PORT', 80)))