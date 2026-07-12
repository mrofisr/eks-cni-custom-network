.PHONY: init plan apply destroy fmt validate clean output state-list

TF_DIR := terraform

init:
	cd $(TF_DIR) && terraform init

plan:
	cd $(TF_DIR) && terraform plan -out=tfplan

apply:
	cd $(TF_DIR) && terraform apply tfplan

apply-auto:
	cd $(TF_DIR) && terraform apply -auto-approve

destroy:
	cd $(TF_DIR) && terraform destroy

fmt:
	cd $(TF_DIR) && terraform fmt -recursive -diff

validate:
	cd $(TF_DIR) && terraform validate

clean:
	rm -rf $(TF_DIR)/.terraform $(TF_DIR)/tfplan $(TF_DIR)/*.tfstate*

output:
	cd $(TF_DIR) && terraform output

state-list:
	cd $(TF_DIR) && terraform state list

console:
	cd $(TF_DIR) && terraform console

docs:
	cd $(TF_DIR) && terraform-docs markdown table . > README.md
