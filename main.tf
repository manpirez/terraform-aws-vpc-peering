module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.3"
  enabled    = "${var.enabled}"
  namespace  = "${var.namespace}"
  name       = "${var.name}"
  stage      = "${var.stage}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
}

resource "aws_vpc_peering_connection" "default" {
  vpc_id      = "${var.requestor_vpc_id}"
  peer_vpc_id = "${var.acceptor_vpc_id}"

  auto_accept = "${var.auto_accept}"

  accepter {
    allow_remote_vpc_dns_resolution = "${var.acceptor_allow_remote_vpc_dns_resolution}"
  }

  requester {
    allow_remote_vpc_dns_resolution = "${var.requestor_allow_remote_vpc_dns_resolution}"
  }

  tags = "${module.label.tags}"
}

# Lookup requestor VPC so that we can reference the CIDR
data "aws_vpc" "requestor" {
  id    = "${var.requestor_vpc_id}"
}

# Lookup requestor route tables
data "aws_route_table" "art_requestor" {
  count     = "${length(distinct(sort(data.aws_subnet_ids.requestor.ids)))}"
  vpc_id    = "${data.aws_vpc.requestor.id}"
  subnet_id = "${element(distinct(sort(data.aws_subnet_ids.requestor.ids)), count.index)}"
}

# Lookup requestor subnets
data "aws_subnet_ids" "requestor" {
  vpc_id = "${data.aws_vpc.requestor.id}"
}

# Lookup acceptor VPC so that we can reference the CIDR
data "aws_vpc" "acceptor" {
  id    = "${var.acceptor_vpc_id}"
}

# Lookup acceptor subnets
data "aws_subnet_ids" "acceptor" {
  vpc_id = "${data.aws_vpc.acceptor.id}"
}

# Lookup acceptor route tables
data "aws_route_table" "acceptor" {
  count     = "${length(distinct(sort(data.aws_subnet_ids.acceptor.ids)))}"
  vpc_id    = "${data.aws_vpc.acceptor.id}"
  subnet_id = "${element(distinct(sort(data.aws_subnet_ids.acceptor.ids)), count.index)}"
}

# Create routes from requestor to acceptor
resource "aws_route" "ar_requestor" {
  count                     = "${length(distinct(sort(data.aws_route_table.art_requestor.*.route_table_id))) * length(data.aws_vpc.acceptor.cidr_block_associations)}"
  route_table_id            = "${element(distinct(sort(data.aws_route_table.art_requestor.*.route_table_id)), (ceil(count.index / (length(data.aws_vpc.acceptor.cidr_block_associations)))))}"
  destination_cidr_block    = "${lookup(data.aws_vpc.acceptor.cidr_block_associations[count.index % (length(data.aws_vpc.acceptor.cidr_block_associations))], "cidr_block")}"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.default.id}"
  depends_on                = ["data.aws_route_table.art_requestor", "aws_vpc_peering_connection.default"]
}

# Create routes from acceptor to requestor
resource "aws_route" "acceptor" {
  count                     = "${length(distinct(sort(data.aws_route_table.acceptor.*.route_table_id))) * length(data.aws_vpc.requestor.cidr_block_associations)}"
  route_table_id            = "${element(distinct(sort(data.aws_route_table.acceptor.*.route_table_id)), ceil(count.index / (length(data.aws_vpc.requestor.cidr_block_associations))))}"
  destination_cidr_block    = "${lookup(data.aws_vpc.requestor.cidr_block_associations[count.index % (length(data.aws_vpc.requestor.cidr_block_associations))], "cidr_block")}"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.default.id}"
  depends_on                = ["data.aws_route_table.acceptor", "aws_vpc_peering_connection.default"]
}
