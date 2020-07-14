provider "aws" {
	region = "ap-south-1"
	profile = "sky"
}

# -- Creating Key pairs

resource "tls_private_key" "key1" {
	algorithm = "RSA"
	rsa_bits = 4096
}

resource "local_file" "key2" {
	content = "${tls_private_key.key1.private_key_pem}"
	filename = "task1_key.pem"
	file_permission = 0400
}

resource "aws_key_pair" "key3" {
	key_name = "task1_key"
	public_key = "${tls_private_key.key1.public_key_openssh}"
}

# -- Creating Security Groups

resource "aws_security_group" "sg" {
	name        = "task1-sg"
  	description = "Allow TLS inbound traffic"
  	vpc_id      = "vpc-ebf8e583"


  	ingress {
    		description = "SSH"
    		from_port   = 22
    		to_port     = 22
    		protocol    = "tcp"
    		cidr_blocks = [ "0.0.0.0/0" ]
  	}

  	ingress {
    		description = "HTTP"
    		from_port   = 80
    		to_port     = 80
    		protocol    = "tcp"
    		cidr_blocks = [ "0.0.0.0/0" ]
  	}

  	egress {
    		from_port   = 0
    		to_port     = 0
    		protocol    = "-1"
    		cidr_blocks = ["0.0.0.0/0"]
  	}

  	tags = {
    		Name = "task1-sg"
  	}
}

# -- Creating Ec2 instance

resource "aws_instance" "web_server" {
  	ami = "ami-0447a12f28fddb066"
  	instance_type = "t2.micro"
 	subnet_id = "subnet-adead0c5"
	availability_zone = "ap-south-1a"
	root_block_device {
		volume_type = "gp2"
		delete_on_termination = true
	}
  	key_name = "${aws_key_pair.key3.key_name}"
  	security_groups = [ aws_security_group.sg.id ]

  	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = "${tls_private_key.key1.private_key_pem}"
    		host     = "${aws_instance.web_server.public_ip}"
  	}

  	provisioner "remote-exec" {
    		inline = [
      			"sudo yum install httpd git -y",
      			"sudo systemctl restart httpd",
      			"sudo systemctl enable httpd",
    		]
  	}

  	tags = {
    		Name = "task1_os"
  	}

}

# -- Creating EBS volume

resource "aws_ebs_volume" "task1_ebs" {
  	availability_zone = "ap-south-1a" 
  	size = 1
	type = "gp2"
  	tags = {
   		Name = "task1_ebs"
  	}
}


# -- Mounting the ebs volume

resource "aws_volume_attachment" "task1_ebs_mount" {
  	device_name = "/dev/xvds"
  	volume_id   = "${aws_ebs_volume.task1_ebs.id}"
  	instance_id = "${aws_instance.web_server.id}"
  	force_detach = true
	
	
  	connection {
    		type     = "ssh"
    		user     = "ec2-user"
   		private_key = "${tls_private_key.key1.private_key_pem}"
    		host     = "${aws_instance.web_server.public_ip}"
  	}

	provisioner "remote-exec" {
    		inline = [
      			"sudo mkfs.ext4  /dev/xvds",
      			"sudo mount  /dev/xvds  /var/www/html",
      			"sudo rm -rf /var/www/html/*",
      			"sudo git clone https://github.com/Akashdeep-47/cloud_task1.git /var/www/html/"
    		]
	  }
}

# -- Creating S3 Bucket

resource "aws_s3_bucket" "mybucket"{
	bucket = "sky25"
	acl = "public-read"

	provisioner "local-exec" {
		command = "git clone https://github.com/Akashdeep-47/cloud_task1.git" 
	}
	
	provisioner "local-exec" {
		when = destroy 
		command = "echo y | rmdir /s cloud_task1"
	}
}

# -- Uploading files in S3 bucket

resource "aws_s3_bucket_object" "file_upload" {
	depends_on = [
    		aws_s3_bucket.mybucket,
  	]
  	bucket = "${aws_s3_bucket.mybucket.bucket}"
  	key    = "my_pic.jpg"
  	source = "cloud_task1/pic.jpg"
	acl ="public-read"
}

# -- Creating CloudFront

resource "aws_cloudfront_distribution" "s3_distribution" {
	depends_on = [
		aws_volume_attachment.task1_ebs_mount,
    		aws_s3_bucket_object.file_upload,
  	]

	origin {
		domain_name = "${aws_s3_bucket.mybucket.bucket}.s3.amazonaws.com"
		origin_id = "ak" 
        }

	enabled = true
	is_ipv6_enabled = true
	default_root_object = "index.html"

	restrictions {
		geo_restriction {
			restriction_type = "none"
 		 }
 	    }

	default_cache_behavior {
		allowed_methods = ["HEAD", "GET"]
		cached_methods = ["HEAD", "GET"]
		forwarded_values {
			query_string = false
			cookies {
				forward = "none"
			}
		}
		default_ttl = 3600
		max_ttl = 86400
		min_ttl = 0
		target_origin_id = "ak"
		viewer_protocol_policy = "allow-all"
		}

	price_class = "PriceClass_All"

	 viewer_certificate {
   		 cloudfront_default_certificate = true
  	}		
}

# -- Updating file to main lacation 

resource "null_resource" "nullremote3"  {
	depends_on = [
    		aws_cloudfront_distribution.s3_distribution,
  	]

	connection {
    		type     = "ssh"
    		user     = "ec2-user"
   		private_key = "${tls_private_key.key1.private_key_pem}"
    		host     = "${aws_instance.web_server.public_ip}"
  	}
	
	provisioner "remote-exec" {
    		inline = [
			"sudo sed -i 's@twerk@http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.file_upload.key}@g' /var/www/html/index.html",
			"sudo systemctl restart httpd"
    		]
	}
}

# -- Staring chrome for output

resource "null_resource" "nulllocal1"  {
	depends_on = [
    		null_resource.nullremote3,
  	]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.web_server.public_ip}"
  	}
}


