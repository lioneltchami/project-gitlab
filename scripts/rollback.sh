#!/bin/bash
set -e

ENVIRONMENT=$1
NAMESPACE="shakespeare-${ENVIRONMENT}"

if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 <environment>"
    exit 1
fi

echo "Rolling back Shakespeare app in $ENVIRONMENT environment"

case $ENVIRONMENT in
    "dev")
        WORDS=("the" "coffee")
        ;;
    "prod")
        WORDS=("the" "coffee" "and" "tea")
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac

echo "Words to rollback: ${WORDS[*]}"

rollback_deployment() {
    local WORD=$1
    local DEPLOYMENT_NAME="shakespeare-$WORD"
    
    echo "Rolling back deployment: $DEPLOYMENT_NAME"
    
    if kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE >/dev/null 2>&1; then
        echo "Rollout history for $DEPLOYMENT_NAME:"
        kubectl rollout history deployment/$DEPLOYMENT_NAME -n $NAMESPACE
        
        kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE
        
        echo "Waiting for rollback to complete..."
        kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s
        
        echo "Rollback completed for $DEPLOYMENT_NAME"
    else
        echo "Deployment $DEPLOYMENT_NAME not found in namespace $NAMESPACE"
    fi
}

verify_service_health() {
    local WORD=$1
    local SERVICE_NAME="shakespeare-$WORD-service"
    
    echo "Verifying health for service: $SERVICE_NAME"
    
    if kubectl get service $SERVICE_NAME -n $NAMESPACE >/dev/null 2>&1; then
        local ENDPOINT=$(kubectl get service $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
        echo "   Service endpoint: $ENDPOINT:80"
        
        local READY_PODS=$(kubectl get pods -l app=shakespeare,word=$WORD -n $NAMESPACE --no-headers 2>/dev/null | grep "Running" | wc -l)
        local TOTAL_PODS=$(kubectl get pods -l app=shakespeare,word=$WORD -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
        
        if [ "$READY_PODS" -gt 0 ]; then
            echo "   $READY_PODS/$TOTAL_PODS pods running"
        else
            echo "   No pods running for word: $WORD"
        fi
    else
        echo "   Service $SERVICE_NAME not found"
    fi
}

echo ""
echo "Starting rollback process..."

for WORD in "${WORDS[@]}"; do
    echo ""
    echo "================================================"
    echo "Processing word: $WORD"
    echo "================================================"
    rollback_deployment $WORD
done

echo ""
echo "Checking ingress configuration..."
if kubectl get ingress shakespeare-ingress -n $NAMESPACE >/dev/null 2>&1; then
    echo "Ingress configuration exists"
    kubectl get ingress shakespeare-ingress -n $NAMESPACE
else
    echo "Ingress not found - may need manual restoration"
fi

echo ""
echo "Waiting for services to stabilize..."
sleep 10

echo ""
echo "Verifying service health after rollback..."
for WORD in "${WORDS[@]}"; do
    verify_service_health $WORD
done

echo ""
echo "================================================"
echo "Final Rollback Status"
echo "================================================"

echo "All pods in namespace $NAMESPACE:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "All services in namespace $NAMESPACE:"
kubectl get services -n $NAMESPACE

echo ""
echo "Checking for ongoing rollouts..."
for WORD in "${WORDS[@]}"; do
    if kubectl get deployment shakespeare-$WORD -n $NAMESPACE >/dev/null 2>&1; then
        local STATUS=$(kubectl rollout status deployment/shakespeare-$WORD -n $NAMESPACE --timeout=1s 2>/dev/null || echo "In progress")
        if [[ "$STATUS" == *"successfully rolled out"* ]]; then
            echo "shakespeare-$WORD: Stable"
        else
            echo "shakespeare-$WORD: Still rolling out"
        fi
    fi
done

echo ""
echo "Rollback process completed!"
echo ""
echo "Next steps:"
echo "   1. Verify application functionality by testing endpoints"
echo "   2. Monitor logs: kubectl logs -f -l app=shakespeare -n $NAMESPACE"
echo "   3. Check metrics and monitoring dashboards"
echo "   4. If issues persist, consider emergency procedures"

echo ""
echo "Useful commands for monitoring:"
echo "   kubectl get pods -n $NAMESPACE --watch"
echo "   kubectl logs -f -l app=shakespeare -n $NAMESPACE"
echo "   kubectl describe pods -l app=shakespeare -n $NAMESPACE"