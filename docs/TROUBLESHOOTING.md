# 🔧 Kubernetes Troubleshooting Guide

Common issues and solutions when working with the any Kubernetes project (Specifically added detailed command w.r.t this project).

## 🚨 Common Issues & Solutions

#### Problem: Container Crashes (CrashLoopBackOff)
```bash

# Describe resource
kubectl describe pod <pod-name> -n shopnow-demo

# Check pod logs
kubectl logs <pod-name> -n shopnow-demo --previous

# Debug with interactive shell
kubectl exec -it <pod-name> -n shopnow-demo -- /bin/sh
```

### Networking Issues

#### Problem: Service Not Accessible
```bash
# Verify service endpoints
kubectl get endpoints -n shopnow-demo

# Test service connectivity
kubectl run debug --image=busybox -it --rm -- nslookup backend.shopnow-demo

# Check service configuration
kubectl describe service backend -n shopnow-demo
```

#### Problem: Ingress Not Working
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Verify ingress resource
kubectl describe ingress shopnow-ingress -n shopnow-demo

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### Storage Issues

#### Problem: Persistent Volume Claims Pending
```bash
# Check available storage classes
kubectl get storageclass

# Verify PVC status
kubectl describe pvc mongo-data-mongo-0 -n shopnow-demo

# Check node storage capacity
kubectl describe nodes
```

### Configuration Issues

#### Problem: ConfigMap/Secret Not Loading
```bash
# Verify ConfigMap exists
kubectl get configmap -n shopnow-demo

# Check secret data
kubectl get secret db-secret -n shopnow-demo -o yaml

# Validate environment variables in pod
kubectl exec <pod-name> -n shopnow-demo -- env | grep MONGODB
```

### Scaling Issues

#### Problem: HPA Not Scaling
```bash
# Check metrics server
kubectl top nodes
kubectl top pods -n shopnow-demo

# Verify HPA status
kubectl describe hpa backend-hpa -n shopnow-demo

# Check resource requests/limits
kubectl describe deployment backend -n shopnow-demo
```

## 🔍 Debugging Commands

### Essential Debugging Toolkit
```bash
# Pod inspection
kubectl get pods -n shopnow-demo -o wide
kubectl describe pod <pod-name> -n shopnow-demo
kubectl logs <pod-name> -n shopnow-demo --follow

# Service debugging
kubectl get svc -n shopnow-demo
kubectl get endpoints -n shopnow-demo

# Network debugging
kubectl exec -it <pod-name> -n shopnow-demo -- nslookup kubernetes.default
kubectl exec -it <pod-name> -n shopnow-demo -- wget -qO- http://backend:5000/health

# Resource monitoring
kubectl top pods -n shopnow-demo
kubectl describe node <node-name>

# Event monitoring
kubectl get events -n shopnow-demo --sort-by='.lastTimestamp'
```

## 🛠 Helm Troubleshooting

### Common Helm Issues
```bash
# Check Helm release status
helm status shopnow-backend -n shopnow-demo

# Debug template rendering
helm template shopnow-backend kubernetes/helm/charts/backend --debug

# Rollback failed deployment
helm rollback shopnow-backend 1 -n shopnow-demo

# Check Helm history
helm history shopnow-backend -n shopnow-demo
```

## 🔄 ArgoCD Troubleshooting

### ArgoCD Sync Issues
```bash
# Check application status
kubectl get applications -n argocd

# View application details
kubectl describe application shopnow-umbrella -n argocd

# Force sync
argocd app sync shopnow-umbrella

# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server
```

## 📊 Performance Troubleshooting

### Resource Monitoring
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -n shopnow-demo

# Detailed resource metrics
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

## 🚨 Emergency Procedures

### Cluster Recovery
```bash
# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Restart failed deployments
kubectl rollout restart deployment/backend -n shopnow-demo

# Emergency pod deletion
kubectl delete pod <pod-name> -n shopnow-demo --force --grace-period=0
```