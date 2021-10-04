#!/usr/bin/env bash

#################### configs #######################

    source secrets/config-values.env
    ADOPTER_CHECK_IMAGE_LOCATION=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$ADOPTER_CHECK_TBS_IMAGE:$APP_VERSION

#################### menu functions #######################

workload () {

    case $1 in
    backend)
        if [ "$2" == "-u" ]
        then
            patch-backend
        else
            create-backend
        fi
        ;;
    frontend)
        create-frontend 
        ;;
    adopter-check)
        if [ "$2" == "-u" ]
        then
            update-adopter-check
        else
            create-adopter-check
        fi
        ;;
    fitness)
        create-fitness
        ;;
    *)
  	    usage
  	    ;;
    esac
}

#################### core functions #######################

#TAP experimental workflow for adopter-check
adopter-check-tap()
    {
        #backend workload
        tanzu apps workload create adopter-check -f workloads/dekt4pets/adopter-check/carto/workload.yaml -y
        tanzu apps workload tail adopter-check --since 1h

        #verify workload deployments
        tanzu apps workload list
    }

#create-backend 
create-backend() {

    echo "Syncing local code with remote git..."
    echo "$DEMO_APP_GIT_REPO/backend remote git synced (no change)"
    echo
    #git-push "local-development-completed"
    #codechanges=$?

    kp image patch $BACKEND_TBS_IMAGE -n $APP_NAMESPACE
    
    echo
    echo "Apply backend app, service and routes ..."
    kustomize build workloads/dekt4pets/backend | kubectl apply -f -
    
}

#create-frontend 
create-frontend() {
	
    echo "Syncing local code with remote git..."
    echo "$DEMO_APP_GIT_REPO/frontend remote git synced (no change)"
    echo

    kp image patch $FRONTEND_TBS_IMAGE -n $APP_NAMESPACE

    echo
    echo "Apply frontend app, service and routes ..."
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
    kubectl apply -f workloads/dekt4pets/backend/config/dekt4pets-backend-app.yaml -n $APP_NAMESPACE
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-routes.yaml -n $APP_NAMESPACE
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $APP_NAMESPACE

}

#dekt4pets
dekt4pets() {

    echo
    echo "${bold}Dekt4pets supply-chain components${normal}"
    echo "-------------------------------------"

    supply-chain-components

    echo
    echo "${bold}Hit any key to start deploying dekt4pets workloads to production...${normal}"
    echo
    read

    echo
    echo "=========> dekt4pets-backend route mapping change to production gateway ..."
    echo
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $APP_NAMESPACE

    echo
    echo "=========> dekt4pets-frontend route mapping change to production gateway..."
    echo
    kubectl apply -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $APP_NAMESPACE

    echo
    echo "=========> dekt4pets micro-gateway (w/ external traffic)..."
    echo
    kustomize build workloads/dekt4pets/gateway | kubectl apply -f -
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
        --env REV="revision 1 of dekt4pets-native-frontend" \
        --revision-name dekt4pets-frontend-v1 \
        -n dekt-apps 

    kn service create dekt4pets-backend \
        --image harbor.apps.cf.tanzutime.com/dekt-apps/dekt4pets-backend:1.0.0\
        --env REV="revision 1 of dekt4pets-native-backend" \
        --revision-name dekt4pets-backend-v1 \
        -n dekt-apps
}


#adopter-check
create-adopter-check () {

    kn service create adopter-check \
        --image $ADOPTER_CHECK_IMAGE_LOCATION \
        --env REV="1.0" \
        --revision-name adopter-check-v1 \
        --namespace $APP_NAMESPACE
}

update-adopter-check () {

    echo

    wait-for-tbs $ADOPTER_CHECK_TBS_IMAGE

    echo
    echo "Starting to tail build logs ..."
    echo

    kp build logs $ADOPTER_CHECK_TBS_IMAGE -n $APP_NAMESPACE

    kn service update $ADOPTER_CHECK_TBS_IMAGE \
        --image $ADOPTER_CHECK_IMAGE_LOCATION \
        --env REV="2.0" \
        --revision-name adopter-check-v2 \
        --traffic adopter-check-v2=70,adopter-check-v1=30 \
        --namespace $APP_NAMESPACE

    kn service describe adopter-check -n $APP_NAMESPACE
}


#delete-workloads
delete-workloads() {

    echo
    echo "=========> Remove all workloads..."
    echo

    #kustomize build workloads/dekt4pets/gateway | kubectl delete -f -  
    kustomize build workloads/dekt4pets/backend | kubectl delete -f -  
    kustomize build workloads/dekt4pets/frontend | kubectl delete -f -  
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $APP_NAMESPACE
    kubectl delete -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $APP_NAMESPACE

    kustomize build workloads/dektFitness/kubernetes-manifests/ | kubectl delete -f -  

    kn service delete adopter-check -n $APP_NAMESPACE 

    #kn service delete dekt-fortune -n $APP_NAMESPACE 

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

wait-for-tbs () {

    image_name=$1

    status=""
    printf "Waiting for tanzu build service to start building $image_name image."
    while [ "$status" == "" ]
    do
        printf "."
        status="$(kp image status $image_name -n dekt-apps | grep 'Building')" 
        sleep 1
    done
    echo
}


#usage
usage() {

    echo
	echo "A mockup script to illustrate upcoming App Stack concepts. Please specify one of the following:"
	echo
    echo "${bold}backend${normal} - deploy the dekt4pets backend service and APIs"
    echo
    echo "${bold}frontend${normal} - deploy the dekt4pets frotend service and APIs"
    echo
    echo "${bold}dekt4pets${normal} - run end-to-end supplychain for dekt4pets deployment to production"
    echo
    echo "${bold}adopter-check${normal} - deploy the dekt4pets adopter check function"
    echo
    echo "${bold}fitness${normal} - deploy the Fitenss app, services and APIs"
    echo
    echo "${bold}fortune${normal} - deploy the fortune backend service and App Viewer sidecar"
    echo
    echo "(use -u for update)"
  	exit   
 
}

#supplychain-dekt4pets
supply-chain-components() {

    echo
    echo "${bold}TAP installed packages${normal}"
    echo
    tanzu package available list -n tap-install
    echo

    echo "${bold}Workload Repositories${normal}"
    echo
    echo "NAME                      URL                                               STATUS"
    echo "dekt4pets-backend         https://github.com/dektlong/dekt4pets-backend     Fetched revision: main"
    echo "dekt4pets-frontend        https://github.com/dektlong/dekt4pets-frontend    Fetched revision: main"
    echo "adopter-check             https://github.com/dektlong/adopter-check         Fetched revision: main"
    echo
    echo "${bold}Workload Images${normal}"
    echo
    kp images list -n $APP_NAMESPACE
    echo "${bold}Cluster Builders${normal}"
    echo
    kp builder list -n $APP_NAMESPACE
    echo "${bold}Delivery Flow${normal}"
    echo
    echo "NAME                          KIND                PATH"
    echo "dekt4pets-backend             app                 workloads/dekt4pets/backend/config/dekt4pets-backend.yaml"
    echo "dekt4pets-backend-routes      api-routes          workloads/dekt4pets/backend/routes/dekt4pets-backend-routes.yaml"
    echo "dekt4pets-backend-mapping     route-mapping       workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml"
    echo
    echo "dekt4pets-frontend            app                 workloads/dekt4pets/frontend/config/dekt4pets-frontend.yaml"
    echo "dekt4pets-frontend-routes     api-routes          workloads/dekt4pets/frontend/routes/dekt4pets-frontend-routes.yaml"
    echo "dekt4pets-frontend-mapping    route-mapping       workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml"
    echo
    echo "dekt4pets-gateway             gateway-config      workloads/dekt4pets/gateway/config/dekt4pets-gateway.yaml"
    echo "dekt4pets-ingress             ingress-rule        workloads/dekt4pets/gateway/config/dekt4pets-ingress.yaml"
    echo "api-portal-ingress            ingress-rule        platform/api-portal/config/api-portal-ingress.yaml"
    echo "openapi-ingress               ingress-rule        platform/api-portal/config/scg-openapi-ingress.yaml"
    echo
    echo "adopter-check                 knative function    "
    echo
}


#################### main #######################

bold=$(tput bold)
normal=$(tput sgr0)

case $1 in
backend)
	workload backend $2
    ;;
frontend)
	workload frontend $2
    ;;
dekt4pets)
    dekt4pets
    ;;
adopter-check)
	workload adopter-check $2
    ;;
fitness)
	workload fitness $2
    ;;
fortune)
	workload fortune $2
    ;;
cleanup)
    delete-workloads
    ;;
*)
  	usage
  	;;
esac
