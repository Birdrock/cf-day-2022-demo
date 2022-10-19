#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../" && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"


echo "**************************************"
echo "Deploying Korifi..."
echo "helm upgrade --install korifi helm/korifi --namespace korifi --values=scripts/assets/values.yaml"
echo "**************************************"
read -p "Press ENTER to continue..."
${SCRIPT_DIR}/deploy-korifi.sh kind

echo "**************************************"
echo "Targeting Korifi..."
echo "**************************************"
read -p "Press ENTER to continue..."
cf api https://localhost --skip-ssl-validation

echo "**************************************"
echo "Login to Korifi..."
echo "**************************************"
read -p "Press ENTER to continue..."
cf login

echo "**************************************"
echo "Creating Org and Space..."
echo "**************************************"
read -p "Press ENTER to continue..."
cf create-org my-org && cf create-space my-space -o my-org && cf target -o my-org

echo "**************************************"
echo "Pushing spring-music..."
echo "**************************************"
read -p "Press ENTER to continue..."
cf push spring-music -p ${ROOT_DIR}/spring-music

echo "**************************************"
echo "Note that changes are not persisted since it is using an in memory database"
echo "**************************************"
read -p "Press ENTER to continue..."
open "https://spring-music.vcap.me"

echo "**************************************"
echo "Creating spring-music-db and associated service..."
echo "**************************************"
read -p "Press ENTER to continue..."
kubectl apply -f ${ROOT_DIR}/spring-music-db/service.yaml

# Note - credentials here are an example and not used in any non-local instance
echo "**************************************"
echo "Creating User Provided Service Instance..."
echo "cf cf create-user-provided-service spring-music-db -p '{\"uri\":\"mysql://user:pass@spring-music-db.default.svc.cluster.local:3306/default\"}'"
echo "**************************************"
read -p "Press ENTER to continue..."
cf cups spring-music-db -p '{"uri":"mysql://user:pass@spring-music-db.default.svc.cluster.local:3306/default"}'

echo "**************************************"
echo "Binding User Provided Service Instance..."
echo "**************************************"
read -p "Press ENTER to continue..."
cf bind-service spring-music spring-music-db

echo "**************************************"
echo "Restaging spring-music..."
echo "**************************************"
read -p "Press ENTER to continue..."
cf restage spring-music

echo "**************************************"
echo "Changes now persist!" 
echo "**************************************"
