
# ... Variable for image_id & Avalability Zone ...

variable "image_id" {
  type = string
  default = "ami-0447a12f28fddb066"
}

variable "availability_zone_names" {
  type    = string
  default = "ap-south-1"
}



# ... aws Provider ...

provider "aws" {
  region = var.availability_zone_names
  profile = "nikhil"
}


# ... aws Security Group ...


resource "aws_security_group" "ssh_http_protocol" {

  name        = "task1_ssh_http"
  description = "Allow http and ssh inboud traffic for task1"

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  /*egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }*/

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  tags = {
    Name = "task1_ssh_http"
  }
}


# ... AWS Key ...

resource "tls_private_key" "key_generated" {
  
  depends_on = [
      aws_security_group.ssh_http_protocol,
  ]

  algorithm  = "RSA"
  rsa_bits   = 4096

}

resource "aws_key_pair" "used_key" {

  key_name   = "HCaws_key"
  public_key = tls_private_key.key_generated.public_key_openssh

}

output "key_ssh" {

  value = tls_private_key.key_generated.private_key_pem

}

resource "local_file" "save_key" {

    content  = tls_private_key.key_generated.private_key_pem
    filename = "HC_task_1_key.pem"

}


# ... AWS EC2 Instance ...


resource "aws_instance" "web" {

  depends_on = [
             tls_private_key.key_generated,
             aws_key_pair.used_key,
             local_file.save_key,
             aws_security_group.ssh_http_protocol
  ]


  ami             = var.image_id
  instance_type   = "t2.micro"
  key_name        = "HCaws_key"
  security_groups = [ "task1_ssh_http" ]


  tags = {
    Name = "nikos1"
  }

}


# ... AWS EBS Volume ...

resource "aws_ebs_volume" "ebs1" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "nikebs"
  }
}



# ... AWS Volume Attachment ...

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.web.id
  force_detach = true
}




# ... Public IP Display on terminal ...

output "myos_ip" {
  value = aws_instance.web.public_ip
}


# ... public IP Stored in a file ...

resource "null_resource" "null_1_local"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.web.public_ip} > publicip.txt"
  	}
}


# ...Public installing httpd, git and formatting Pendrive Created(i.e EBS_Volume) and cloning git ...


resource "null_resource" "null_2_remote"  {
 
  depends_on = [
     aws_instance.web,
     local_file.save_key,
     aws_volume_attachment.ebs_att,
   ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key_generated.private_key_pem
    host        = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
          "sudo yum install httpd php git -y",
          "sudo systemctl restart httpd",
          "sudo systemctl enable httpd",
          "sudo mkfs.ext4  /dev/xvdh",
          "sudo mount  /dev/xvdh  /var/www/html",
          "sudo rm -rf /var/www/html/*",
          "sudo git clone https://github.com/ANikhilAgarwal/Hybridcloud_terraform.git  /var/www/html/"
    ]
  }
}



# ... cloning git on the system to get the image and use it further to store in S3 Bucket ...



resource "null_resource" "null_3_local"  {
  provisioner "local-exec" {
      command = "git clone https://github.com/ANikhilAgarwal/Hybridcloud_terraform.git ./HC_code"
    }
}    


# ... AWS S3 bucket created ...


resource "aws_s3_bucket" "s3_bucket1" {
  depends_on = [
             tls_private_key.key_generated,
             aws_key_pair.used_key,
             local_file.save_key,
             aws_security_group.ssh_http_protocol,
             aws_instance.web
  ]

  bucket = "hcs3bucket1"
  acl    = "public-read"

  tags = {
    Name        = "Hybridcloud_terraform"
   /* Environment = "Dev" */
  }
}



# ... AWS S3 bucket object i.e image is added to the S3 bucket ...

resource "aws_s3_bucket_object" "image" {
  depends_on = [
          aws_s3_bucket.s3_bucket1
  ]

  bucket        = aws_s3_bucket.s3_bucket1.id
  key           = "smile.jpg"
  source        = "./HC_code/smile.jpg"
  acl           = "public-read"
  //force_destroy = "true"

}


# ... AWS CloudFront distribution Creation ...


resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  depends_on = [
          aws_s3_bucket.s3_bucket1,
  ]
 
  comment = "Some comment"
}

resource "aws_cloudfront_distribution" "s3_cloudfront1" {
  depends_on = [
         aws_s3_bucket.s3_bucket1,
         aws_cloudfront_origin_access_identity.origin_access_identity
  ]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-hcs3bucket1"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
  }
  viewer_protocol_policy = "allow-all"
  min_ttl = 0
  default_ttl = 3600
  max_ttl = 86400
}
  
  origin {
    domain_name = aws_s3_bucket.s3_bucket1.bucket_domain_name
    origin_id   = "S3-hcs3bucket1"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
 
  comment             = "Some comment"
  //default_root_object = "index.html"

  /*logging_config {
    include_cookies = false
    bucket          = "mylogs.s3.amazonaws.com"
    prefix          = "myprefix"
  }*/

  // aliases = ["mysite.example.com", "yoursite.example.com"]

  /*# Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.s3_bucket1.id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.s3_bucket1.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"*/

/*
  tags = {
    Environment = "production"
  }
*/

  restrictions {
      geo_restriction {
        restriction_type = "none"
      }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

}



# ... Copying the Cloudfront Generated URl into Another file in the local system ...


resource "null_resource" "null_4_local"  {

  provisioner "local-exec" {
      command = "echo ${aws_cloudfront_distribution.s3_cloudfront1.domain_name}/${aws_s3_bucket_object.image.key} > cloudfrontURL.txt"
    }
}





# ... running the public IP in the chrome browser ...


resource "null_resource" "null_5_local"  {
  depends_on = [
      null_resource.null_2_remote,
      null_resource.null_6_remote
   ]
   
   provisioner "local-exec" {
	    command = "google-chrome  ${aws_instance.web.public_ip}"
   }
}




# ... running the CloudFront Generated URL in the Chrome Browser ...



resource "null_resource" "null_6_remote"  {
  depends_on = [
      null_resource.null_4_local,
   ]
   
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key_generated.private_key_pem
    host        = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
        "sudo su << EOF",
        "sudo echo \"<img src='http://${aws_cloudfront_distribution.s3_cloudfront1.domain_name}/${aws_s3_bucket_object.image.key}'>\" >> /var/www/html/index.html",
        "EOF"
    ]
  }
   provisioner "local-exec" {
	    command = "google-chrome  ${aws_cloudfront_distribution.s3_cloudfront1.domain_name}"
   }
}


