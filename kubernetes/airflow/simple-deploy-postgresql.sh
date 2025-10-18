#!/bin/bash

# Simple PostgreSQL deployment - just deploy the pods with existing storage
echo "🚀 Simple PostgreSQL deployment..."

echo "Current PVC status:"
kubectl get pvc -n airflow | grep postgresql

echo ""
echo "Deploying PostgreSQL primary..."
kubectl apply -f kubernetes/airflow/postgresql-primary.yaml

echo ""
echo "✅ PostgreSQL primary deployment started!"
echo "Monitor with: kubectl get pods -n airflow -w"