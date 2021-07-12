output vpc_id {
  value       = aws_vpc.main.id
}

output public_subnet {
  value       = aws_subnet.public.*.id
}

output private_subnet {
  value       = aws_subnet.private.*.id
}

output all_subnet {
  value       = concat(aws_subnet.public.*.id, aws_subnet.private.*.id)
}
