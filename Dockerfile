FROM node:16

# Set the working directory inside the container
WORKDIR /home/ec2-user


# Install Python and pip
RUN  apt-get  update && apt-get install -y python3 python3-pip

# Copy requirements.txt and install Python dependencies
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Copy the Flask app into the container
COPY app.py /home/ec2-user/
COPY templates /home/ec2-user/templates/

COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Set environment variable SECRET_WORD
#ENV SECRET_WORD=${SECRET_WORD:-"default_secret"}

# Expose the port Flask will run on
EXPOSE 5000


CMD ["python3", "app.py"]