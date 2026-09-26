resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "Public-Route-Table"
  }
}
resource "aws_route_table_association" "public" {
    count = 2
    route_table_id = aws_route_table.rt.id
    subnet_id = aws_subnet.subnet[count.index].id
}