#!/bin/bash
set -e

# Deployment script for Shakespeare app
ENVIRONMENT=$1
IMAGE_TAG=$2
NAMESPACE="shakespeare-${ENVIRONMENT}"

if [ -z "$ENVIRONMENT" ] || [ -z "$IMAGE_TAG" ]; then
    echo "Usage: $0 <environment> <image_tag>"
    exit 1
fi

echo "Deploying Shakespeare app to $ENVIRONMENT with tag $IMAGE_TAG"

# Set environment-specific configurations
case $ENVIRONMENT in
    "dev")
        REPLICAS=1
        WORDS=("the" "COFFEE")
        DOMAIN="shakespeare-dev.example.com"
        ;;
    "prod")
        REPLICAS=2
        WORDS=("the" "COFFEE" "AND" "tea")
        DOMAIN="shakespeare.example.com"
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy each word instance
for WORD in "${WORDS[@]}"; do
    echo "Deploying instance for word: $WORD"
    
    # Generate deployment manifest
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shakespeare-$WORD
  namespace: $NAMESPACE
  labels:
    app: shakespeare
    word: $WORD
    environment: $ENVIRONMENT
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: shakespeare
      word: $WORD
  template:
    metadata:
      labels:
        app: shakespeare
        word: $WORD
        environment: $ENVIRONMENT
    spec:
      serviceAccountName: shakespeare-sa
      containers:
      - name: shakespeare-app
        image: $CI_REGISTRY_IMAGE/shakespeare-app:$IMAGE_TAG
        ports:
        - containerPort: 5000
        env:
        - name: WORD
          value: "$WORD"
        - name: PORT
          value: "5000"
        - name: FLASK_ENV
          value: "production"
        - name: GOOGLE_APPLICATION_CREDENTIALS
          value: "/var/secrets/google/service-account.json"
        volumeMounts:
        - name: google-cloud-key
          mountPath: /var/secrets/google
          readOnly: true
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: google-cloud-key
        secret:
          secretName: google-cloud-key
---
apiVersion: v1
kind: Service
metadata:
  name: shakespeare-$WORD-service
  namespace: $NAMESPACE
  labels:
    app: shakespeare
    word: $WORD
spec:
  selector:
    app: shakespeare
    word: $WORD
  ports:
  - port: 80
    targetPort: 5000
  type: ClusterIP
EOF

done

# Create ingress with routing for your specific words
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shakespeare-ingress
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  tls:
  - hosts:
    - $DOMAIN
    secretName: shakespeare-tls
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /the/?(.*)
        pathType: Prefix
        backend:
          service:
            name: shakespeare-the-service
            port:
              number: 80
      - path: /(coffee|COFFEE)/?(.*)
        pathType: Prefix
        backend:
          service:
            name: shakespeare-COFFEE-service
            port:
              number: 80
      - path: /(and|AND)/?(.*)
        pathType: Prefix
        backend:
          service:
            name: shakespeare-AND-service
            port:
              number: 80
      - path: /tea/?(.*)
        pathType: Prefix
        backend:
          service:
            name: shakespeare-tea-service
            port:
              number: 80
      - path: /?(.*)
        pathType: Prefix
        backend:
          service:
            name: shakespeare-the-service
            port:
              number: 80
EOF

echo "Deployment completed successfully!"
echo "Application will be available at: https://$DOMAIN"

# Display access URLs
echo ""
echo "🔗 Access URLs:"
echo "   Main (the):     https://$DOMAIN/"
echo "   The:            https://$DOMAIN/the/"
echo "   Coffee:         https://$DOMAIN/coffee/ or https://$DOMAIN/COFFEE/"
echo "   And:            https://$DOMAIN/and/ or https://$DOMAIN/AND/"
echo "   Tea:            https://$DOMAIN/tea/"
echo ""

# Wait for rollout to complete
echo "⏳ Waiting for deployments to be ready..."
for WORD in "${WORDS[@]}"; do
    echo "Checking rollout status for: $WORD"
    kubectl rollout status deployment/shakespeare-$WORD -n $NAMESPACE --timeout=300s
done

echo "✅ All deployments are ready!"

# Verify health of all services
echo ""
echo "🏥 Checking service health..."
for WORD in "${WORDS[@]}"; do
    echo -n "Checking shakespeare-$WORD-service: "
    if kubectl get service shakespeare-$WORD-service -n $NAMESPACE >/dev/null 2>&1; then
        echo "✅ Service running"
    else
        echo "❌ Service not found"
    fi
done

echo ""
echo "🎉 Deployment complete! Your Shakespeare app is ready."