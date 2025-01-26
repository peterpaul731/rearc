from flask import Flask, render_template, request
import os

app = Flask(__name__)

@app.route('/')        # Public cloud & index page (contains the secret word) 
def index():
    secret_word = os.getenv("SECRET_WORD", "default_secret")  # Returns default vaule if the environment variable not set
    return render_template('index.html', secret_word=secret_word)    # Returns value of set environment variable

@app.route('/docker')   # Docker check
def docker_check():
    return "Docker Container is configured and  Running!!!"

@app.route('/secret_word')  # Secret Word check
def secret_word():
    secret_word = os.getenv('SECRET_WORD', 'default_secret')
    return f"The SECRET_WORD is: {secret_word}"

@app.route('/loadbalanced')
def load_balanced():
    return "Load Balancer is routing the traffic"

@app.route('/tls')  # TLS check
def tls_check():
    # Check if the request is over HTTPS using X-Forwarded-Proto
    proto = request.headers.get('X-Forwarded-Proto', 'http')
    if proto == 'https':
        return "TLS (HTTPS) is working! Connection is secure."
    else:
        return "TLS (HTTPS) is NOT working! Connection is NOT secure."

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)