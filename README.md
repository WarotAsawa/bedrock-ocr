# Bedrock OCR and Thai Translation App

This web application allows users to upload images containing text, extract the text using Amazon Bedrock's Claude 3 model, and translate the extracted text to Thai language.

## Key Features

- **Image Upload Interface**:
  - Drag-and-drop functionality
  - Image preview before submission
  - File type validation (.jpg, .jpeg, .png)
  - User-friendly interface with Bootstrap styling

- **Text Extraction**:
  - Uses Amazon Bedrock's Claude 3 Sonnet model for accurate OCR
  - Processes images to extract text content from various formats
  - Handles multiple languages in source images

- **Thai Translation**:
  - Translates the extracted text to Thai language
  - Uses Claude 3 for high-quality, context-aware translation
  - Proper rendering of Thai characters with appropriate fonts

- **Results Display**:
  - Shows the uploaded image alongside extracted text
  - Displays both original and translated text in a clean interface
  - Option to process additional images

## Prerequisites

- Python 3.8+
- AWS account with access to Amazon Bedrock
- AWS credentials with appropriate permissions

## Installation

1. Clone this repository:
   ```
   git clone <repository-url>
   cd bedrock-ocr
   ```

2. Install the required dependencies:
   ```
   pip install -r requirements.txt
   ```

3. Create a `.env` file based on the `.env.example` file:
   ```
   cp .env.example .env
   ```

4. Edit the `.env` file with your AWS credentials and other configuration:
   ```
   AWS_REGION=us-east-1
   AWS_ACCESS_KEY_ID=your_access_key_id
   AWS_SECRET_ACCESS_KEY=your_secret_access_key
   SECRET_KEY=your_flask_secret_key
   ```

## How to Run the Application

1. Ensure your AWS credentials are properly configured with access to Amazon Bedrock services

2. Start the Flask application:
   ```
   python app.py
   ```

3. Open your web browser and navigate to `http://127.0.0.1:5000`

4. Upload an image containing text using the web interface:
   - Click on the upload area or drag and drop an image
   - Preview the image before submission
   - Click "Extract and Translate Text" button

5. View the results page showing:
   - The uploaded image
   - Extracted original text
   - Thai translation of the text

6. Process additional images by clicking "Process Another Image"

## AWS Permissions Required

The application requires AWS credentials with the following permissions:

- `bedrock:InvokeModel` - To call the Claude 3 model for text extraction and translation
- `bedrock:ListFoundationModels` - To verify model availability (optional)

You may need to request access to Amazon Bedrock models in your AWS account before using this application. Visit the AWS Bedrock console to request model access.

## Technical Implementation Details

- **Flask**: Web framework for handling HTTP requests, routing, and serving pages
- **Boto3**: AWS SDK for Python to interact with Amazon Bedrock services
- **Claude 3 Sonnet**: Foundation model used for both OCR and translation tasks
- **Pillow**: For image processing and manipulation
- **Bootstrap**: For responsive UI design and styling
- **JavaScript**: For client-side image preview and drag-and-drop functionality
- **dotenv**: For environment variable management

The application follows this workflow:
1. User uploads an image through the web interface
2. Image is saved to the server and copied to static directory for display
3. Base64-encoded image is sent to Claude 3 for text extraction
4. Extracted text is sent to Claude 3 for Thai translation
5. Results are displayed to the user in a formatted page

## Project Structure

- `app.py`: Main Flask application with routes and Bedrock integration
- `templates/`: HTML templates
  - `index.html`: Upload page with drag-and-drop functionality
  - `result.html`: Results page showing extracted and translated text
- `static/uploads/`: Directory for serving uploaded images
- `uploads/`: Directory for storing uploaded images
- `requirements.txt`: Python dependencies
- `.env`: Environment variables (not included in repository)
- `.env.example`: Example environment variables template

## License

This project is licensed under the MIT License - see the LICENSE file for details.