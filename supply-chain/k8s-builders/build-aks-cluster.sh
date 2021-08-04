#!/usr/bin/env bash

#################### functions #######################

#create cluster
create-cluster() {
	
	clusterName=$1
	numberOfNodes=$2

	#rm ~/.kube/config

	echo
	echo "==========> Creating AKS cluster named $clusterName with $numberOfNodes nodes ..."
	echo
	
	az login -u $AZURE_USER -p $AZURE_PASSWORD --allow-no-subscriptions
	
	az group create --name $RESOURCE_GROUP --location westus

	az aks create --resource-group $RESOURCE_GROUP --name $clusterName --node-count $numberOfNodes --generate-ssh-keys

	az aks get-credentials --overwrite-existing --resource-group $RESOURCE_GROUP --name $1
}

delete-cluster() {
	
	clusterName=$1

	az login -u $AZURE_USER -p $AZURE_PASSWORD

	echo
	echo "==========> Starting deletion of AKS cluster named $clusterName"
	echo

	az aks delete --name $clusterName --resource-group $RESOURCE_GROUP --yes --no-wait

}

#incorrect usage
incorrect-usage() {
	
	echo "Incorrect usage. Required: create {cluster-name,number-of-worker-nodes} | delete {cluster-name}"
	exit
}


#################### main #######################

source secrets/config-values.env

case $1 in 
create)
	create-cluster $2 $3
	;;
delete)
	delete-cluster $2
  	;;
*)
  	incorrect-usage
  	;;
esac


