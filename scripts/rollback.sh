#!/bin/bash
set -e

# Rollback script for Shakespeare app
ENVIRONMENT=$1
NAMESPACE="shakespeare-${ENVIRONMENT}"

if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 <environment>"
    exit 1
fi

echo "🔄 Rolling back Shakespeare app in $ENVIRONMENT environment"

# Set environment-specific configurations
case $ENVIRONMENT in
    "dev")
        WORDS=("the" "COFFEE")
        ;;
    "prod")
        WORDS=("the" "COFFEE" "AND" "tea")
        ;;
    *)
        echo "❌ Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac

echo "📋 Words to rollback: ${WORDS[*]}"

# Function to rollback a deployment
rollback_deployment() {
    local WORD=$1
    local DEPLOYMENT_NAME="shakespeare-$WORD"
    
    echo "🔄 Rolling back deployment: $DEPLOYMENT_NAME"
    
    # Check if deployment exists
    if kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE >/dev/null 2>&1; then
        # Get rollout history
        echo "📜 Rollout history for $DEPLOYMENT_NAME:"
        kubectl rollout history deployment/$DEPLOYMENT_NAME -n $NAMESPACE
        
        # Rollback to previous revision
        kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE
        
        # Wait for rollback to complete
        echo "⏳ Waiting for rollback to complete..."
        kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s
        
        echo "✅ Rollback completed for $DEPLOYMENT_NAME"
    else
        echo "⚠️  Deployment $DEPLOYMENT_NAME not found in namespace $NAMESPACE"
    fi
}

# Function to verify service health
verify_service_health() {
    local WORD=$1
    local SERVICE_NAME="shakespeare-$WORD-service"
    
    echo "🏥 Verifying health for service: $SERVICE_NAME"
    
    # Check service exists
    if kubectl get service $SERVICE_NAME -n $NAMESPACE >/dev/null 2>&1; then
        # Get service endpoint
        local ENDPOINT=$(kubectl get service $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
        echo "   Service endpoint: $ENDPOINT:80"
        
        # Check if pods are ready
        local READY_PODS=$(kubectl get pods -l app=shakespeare,word=$WORD -n $NAMESPACE --no-headers 2>/dev/null | grep "Running" | wc -l)
        local TOTAL_PODS=$(kubectl get pods -l app=shakespeare,word=$WORD -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
        
        if [ "$READY_PODS" -gt 0 ]; then
            echo "   ✅ $READY_PODS/$TOTAL_PODS pods running"
        else
            echo "   ❌ No pods running for word: $WORD"
        fi
    else
        echo "   ❌ Service $SERVICE_NAME not found"
    fi
}

# Rollback all deployments
echo ""
echo "🚀 Starting rollback process..."

for WORD in "${WORDS[@]}"; do
    echo ""
    echo "================================================"
    echo "Processing word: $WORD"
    echo "================================================"
    rollback_deployment $WORD
done

# Verify ingress is still working
echo ""
echo "🌐 Checking ingress configuration..."
if kubectl get ingress shakespeare-ingress -n $NAMESPACE >/dev/null 2>&1; then
    echo "✅ Ingress configuration exists"
    kubectl get ingress shakespeare-ingress -n $NAMESPACE
else
    echo "⚠️  Ingress not found - may need manual restoration"
fi

# Wait a moment for services to stabilize
echo ""
echo "⏳ Waiting for services to stabilize..."
sleep 10

# Verify all services are healthy
echo ""
echo "🏥 Verifying service health after rollback..."
for WORD in "${WORDS[@]}"; do
    verify_service_health $WORD
done

# Display final status
echo ""
echo "================================================"
echo "📊 Final Rollback Status"
echo "================================================"

# Show all pods in namespace
echo "All pods in namespace $NAMESPACE:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "All services in namespace $NAMESPACE:"
kubectl get services -n $NAMESPACE

# Check if any deployments are still rolling out
echo ""
echo "🔄 Checking for ongoing rollouts..."
for WORD in "${WORDS[@]}"; do
    if kubectl get deployment shakespeare-$WORD -n $NAMESPACE >/dev/null 2>&1; then
        local STATUS=$(kubectl rollout status deployment/shakespeare-$WORD -n $NAMESPACE --timeout=1s 2>/dev/null || echo "In progress")
        if [[ "$STATUS" == *"successfully rolled out"* ]]; then
            echo "✅ shakespeare-$WORD: Stable"
        else
            echo "⏳ shakespeare-$WORD: Still rolling out"
        fi
    fi
done

echo ""
echo "🎉 Rollback process completed!"
echo ""
echo "📝 Next steps:"
echo "   1. Verify application functionality by testing endpoints"
echo "   2. Monitor logs: kubectl logs -f -l app=shakespeare -n $NAMESPACE"
echo "   3. Check metrics and monitoring dashboards"
echo "   4. If issues persist, consider emergency procedures"

# Provide helpful commands
echo ""
echo "🔧 Useful commands for monitoring:"
echo "   kubectl get pods -n $NAMESPACE --watch"
echo "   kubectl logs -f -l app=shakespeare -n $NAMESPACE"
echo "   kubectl describe pods -l app=shakespeare -n $NAMESPACE"