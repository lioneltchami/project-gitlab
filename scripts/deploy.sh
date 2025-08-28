#!/bin/bash
set -e

ENVIRONMENT=$1
IMAGE_TAG=$2
NAMESPACE="shakespeare-${ENVIRONMENT}"

if [ -z "$ENVIRONMENT" ] || [ -z "$IMAGE_TAG" ]; then
    echo "Usage: $0 <environment> <image_tag>"
    exit 1
fi

echo "Deploying Shakespeare app to $ENVIRONMENT with tag $IMAGE_TAG"

case $ENVIRONMENT in
    "dev")
        REPLICAS=1
        WORDS=("the" "coffee")
        DOMAIN="shakespeare-dev.example.com"
        ;;
    "prod")
        REPLICAS=2
        WORDS=("the" "coffee" "and" "tea")
        DOMAIN="shakespeare.example.com"
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac

kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

for WORD in "${WORDS[@]}"; do
    echo "Deploying instance for word: $WORD"
    
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
        - name: GOOGLE_CLOUD_PROJECT
          value: "$GOOGLE_CLOUD_PROJECT"
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

generate_ingress_paths() {
    local paths=""
    
    paths+="      - path: /
        pathType: Prefix
        backend:
          service:
            name: shakespeare-the-service
            port:
              number: 80"
    
    for WORD in "${WORDS[@]}"; do
        paths+="
      - path: /$WORD/
        pathType: Prefix
        backend:
          service:
            name: shakespeare-$WORD-service
            port:
              number: 80"
    done
    
    echo "$paths"
}

echo "Creating ingress for environment: $ENVIRONMENT with words: ${WORDS[*]}"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shakespeare-ingress
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - $DOMAIN
    secretName: shakespeare-tls
  rules:
  - host: $DOMAIN
    http:
      paths:
$(generate_ingress_paths)
EOF

echo "Deployment completed successfully!"
echo "Application will be available at: https://$DOMAIN"

echo ""
echo "Access URLs for $ENVIRONMENT environment:"
echo "   Main (the):     https://$DOMAIN/"
for WORD in "${WORDS[@]}"; do
    echo "   $WORD:            https://$DOMAIN/$WORD/"
done
echo ""

echo "Waiting for deployments to be ready..."
for WORD in "${WORDS[@]}"; do
    echo "Checking rollout status for: $WORD"
    kubectl rollout status deployment/shakespeare-$WORD -n $NAMESPACE --timeout=300s
done

echo "All deployments are ready!"

echo ""
echo "Checking service health..."
for WORD in "${WORDS[@]}"; do
    echo -n "Checking shakespeare-$WORD-service: "
    if kubectl get service shakespeare-$WORD-service -n $NAMESPACE >/dev/null 2>&1; then
        echo "Service running"
    else
        echo "Service not found"
    fi
done

echo ""
echo "Deployment complete! Your Shakespeare app is ready."