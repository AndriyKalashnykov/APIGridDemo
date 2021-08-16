#!/usr/bin/env bash

#################### menu functions #######################

#create-workload
create-workload () {

    case $1 in
    backend)
        create-backend
        ;;
    frontend)
        create-frontend 
        ;;
    adopter-check)
        create-adopter-check
        ;;
    fitness)
        create-fitness
        ;;
    fortune)
        create-fortune
        ;;
    *)
  	    usage
  	    ;;
    esac
}

#update-workload
update-workload () {

    case $1 in
    backend)
        patch-backend
        ;;
    check-adpoter)
        update-check-adopter 
        ;;
    fortune)
        update-fortune
        ;;
    *)
  	    usage
  	    ;;
    esac
}

#workload
workload () {

    case $1 in
    create)
        create-workload $2
        ;;
    update)
        update-workload $2
        ;;
    *)
  	    usage
  	    ;;
    esac
}

#supplychain
supplychain () {

    case $1 in
    dekt4pets)
        supplychain-dekt4pets
        ;;
    dektFitness)
        supplychain-dektFitness 
        ;;
    *)
  	    usage
  	    ;;
    esac
}

#################### core functions #######################

#create-backend 
create-backend() {
	
    echo
    echo "=========> Sync local code with remote git $DEMO_APP_GIT_REPO ..."
    echo
    #git-push "local-development-completed"
    #codechanges=$?

    echo
    echo "=========> Invoke image build (if needed)..."
    echo
    kp image patch $BACKEND_TBS_IMAGE -n $APP_NAMESPACE
    echo
    kp build list $BACKEND_TBS_IMAGE -n $APP_NAMESPACE
    
    echo
    echo "=========> Apply backend app, service and routes ..."
    echo    
    #kubectl set image deployment/dekt4pets-backend dekt4pets-backend=$IMG_REGISTRY_URL/$IMG_REGISTRY_APP_REPO/$BACKEND_TBS_IMAGE:$APP_VERSION -n $APP_NAMESPACE
    kustomize build workloads/dekt4pets/backend | kubectl apply -f -
    
}

#create-frontend 
create-frontend() {
	
    echo
    echo "=========> Apply frontend app, service and routes ..."
    echo
	
    kustomize build workloads/dekt4pets/frontend | kubectl apply -f -

}

#patch-backend
patch-backend() {
    
    git_commit_msg="add check-adopter api"
    
    echo
    echo "=========> Commit code changes to $DEMO_APP_GIT_REPO  ..."
    echo
    git-push "$git_commit_msg"
    
    echo
    echo "=========> Auto-build $BACKEND_TBS_IMAGE image on latest git commit (commit: $_latestCommitId) ..."
    echo
    
    kp image patch $BACKEND_TBS_IMAGE --git-revision $_latestCommitId -n $APP_NAMESPACE
    
    echo
    echo "Waiting for next github polling interval ..."
    echo  
    
    #apply new routes so you can show them in portal while new build is happening
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-routes.yaml -n $APP_NAMESPACE >/dev/null &
    
    sleep 10 #enough time, instead of active polling which is not recommended by the TBS team
    
    kp build list $BACKEND_TBS_IMAGE -n $APP_NAMESPACE

    #kp build status $BACKEND_TBS_IMAGE -n $APP_NAMESPACE

    echo
    echo "Starting to tail build logs ..."
    echo
    
    kp build logs $BACKEND_TBS_IMAGE -n $APP_NAMESPACE
    
    echo
    echo "=========> Apply changes to backend app, service and routes ..."
    echo
    
    #workaround for image refresh issue
    kubectl delete -f workloads/dekt4pets/backend/dekt4pets-backend-app.yaml -n $APP_NAMESPACE > /dev/null 
        
    kustomize build workloads/dekt4pets/backend | kubectl apply -f -

}

#deploy-fitness app
create-fitness () {

    pushd workloads/dektFitness

    kustomize build kubernetes-manifests/ | kubectl apply -f -
}

#dekt44pets-native
create-dekt4pets-native () {

    kn service create dekt4pets-frontend \
        --image springcloudservices/animal-rescue-frontend  \
        --env TARGET="revision 1 of dekt4pets-native-frontend" \
        --revision-name dekt4pets-frontend-v1 \
        -n dekt-apps 

    kn service create dekt4pets-backend \
        --image harbor.apps.cf.tanzutime.com/dekt-apps/dekt4pets-backend:1.0.0\
        --env TARGET="revision 1 of dekt4pets-native-backend" \
        --revision-name dekt4pets-backend-v1 \
        -n dekt-apps
}

#dekt-fortune
create-fortune () {

    kn service create dekt-fortune \
        --image harbor.apps.cf.tanzutime.com/dekt-apps/fortune-service:0.0.1 \
        --env TARGET="revision 1 of dekt-fortune" \
        --revision-name dekt-fortune-v1 \
        --namespace $APP_NAMESPACE
}

update-fortune () {
 
    kn service update dekt-fortune \
        --image $IMG_REGISTRY_URL/$IMG_REGISTRY_APP_REPO/fortune-service:0.0.1 \
        --env TARGET="revision 2 of dekt-fortune" \
        --revision-name dekt-fortune-v2 \
        --traffic @latest=20,dekt-fortune-v1=80 \
        --namespace $APP_NAMESPACE 
}

#adopter-check
create-adopter-check () {

    kn service create adopter-check \
        --image $IMG_REGISTRY_URL/$IMG_REGISTRY_APP_REPO/adopter-check:0.0.1 \
        --env TARGET="revision 1 of adopter-check" \
        --revision-name adopter-check-v1 \
        --namespace dekt-apps
}

#delete-workloads
delete-workloads() {

    echo
    echo "=========> Remove all workloads..."
    echo

    kustomize build workloads/dekt4pets/backend | kubectl delete -f -

    kustomize build workloads/dekt4pets/frontend | kubectl delete -f -  

    kustomize build workloads/dektFitness/kubernetes-manifests/ | kubectl delete -f -  

    kn service delete rockme-native -n $APP_NAMESPACE 

}

#################### helper functions #######################

#git-push
#   param: commit message
git-push() {

    #check if this commit will have actual code changes (for later pipeline operations)
    #git diff --exit-code --quiet
    #local_changes=$? #1 if prior to commit any code changes were made, 0 if no changes made

	git commit -a -m "$1"
	git push  
	
    _latestCommitId="$(git rev-parse HEAD)"
}

#usage
usage() {

    echo
	echo "A mockup script to illustrate upcoming App Stack concepts. Please specify one of the following:"
	echo
    echo "${bold}supplychain${normal}"
    echo "  dekt4pets"
    echo "  dektFitness"
    echo
    echo "${bold}workload${normal}"
    echo "  ${bold}create${normal}"
    echo "    backend"
    echo "    frontend"
    echo "    adopter-check"
    echo "    fitness"
    echo "    fortune"
    echo "  ${bold}update${normal}"
    echo "    backend"
    echo "    adopter-check"
    echo "    fortune"
    echo
  	exit   
 
}

#supplychain-dekt4pets
supplychain-dekt4pets() {

    echo
    echo "${bold}dekt4pets supplychain${normal}"
    echo "---------------------"
    echo
    echo "${bold}Workload Repositories${normal}"
    echo "NAME                      URL                                                 STATUS"
    echo "dekt4pets-source          https://github.com/dektlong/_dekt4pets-demo         Fetched revision: main"
    echo
    echo "${bold}Workload Images${normal}"
    kp images list -n $APP_NAMESPACE
    echo "${bold}Cluster Builders${normal}"
    kp builder list -n $APP_NAMESPACE
    echo "${bold}Image Scanners${normal}"
    echo "NAME              URL"
    echo "dekt-scanner      https://github.com/quay/clair"
    echo
    echo "${bold}Delivery${normal}"
    echo "NAME                          KIND                INFO"
    echo "dekt4pets-gateway             gateway-config      config/dekt4pets-gateway.yaml"
    echo "dekt4pets-backend             app                 config/dekt4pets-backend-app.yaml"
    echo "dekt4pets-backend-routes      api-routes          routes/dekt4pets-backend-routes.yaml"
    echo "dekt4pets-backend-mapping     route-mapping       routes/dekt4pets-backend-mapping.yaml"
    echo "dekt4pets-backend             app                 config/dekt4pets-frontend-app.yaml"
    echo "dekt4pets-frontend-routes     api-routes          routes/dekt4pets-frontend-routes.yaml"
    echo "dekt4pets-frontend-mapping    route-mapping       routes/dekt4pets-frontend-mapping.yaml"
    echo
}

#supplychain-dektFitness
supplychain-dektFitness() {

    echo
    echo "${bold}dekt4Fitness supplychain${normal}"
    echo "------------------"
    echo
    echo "WORK IN PROGRESS..."
    echo
}


#################### main #######################

source secrets/config-values.env
bold=$(tput bold)
normal=$(tput sgr0)

case $1 in
supplychain)
	supplychain $2
    ;;
workload)
	workload $2 $3
    ;;
*)
  	usage
  	;;
esac
