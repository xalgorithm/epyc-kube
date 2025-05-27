#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage
function print_usage {
  echo -e "${BLUE}Usage:${NC}"
  echo -e "  $0 [options]"
  echo
  echo -e "${BLUE}Options:${NC}"
  echo -e "  -f, --file PATH        Path to Divi.zip file (required if no URL)"
  echo -e "  -u, --url URL          URL to download Divi.zip (required if no file)"
  echo -e "  -c, --configmap        Use ConfigMap-based job instead of basic job"
  echo -e "  -h, --help             Display this help message"
  echo
  echo -e "${BLUE}Examples:${NC}"
  echo -e "  $0 --file /path/to/Divi.zip"
  echo -e "  $0 --url https://example.com/Divi.zip"
  echo -e "  $0 --file /path/to/Divi.zip --configmap"
}

# Initialize variables
DIVI_FILE=""
DIVI_URL=""
USE_CONFIGMAP=false

# Parse command line arguments
while (( "$#" )); do
  case "$1" in
    -f|--file)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        DIVI_FILE="$2"
        shift 2
      else
        echo -e "${RED}Error: Argument for $1 is missing${NC}" >&2
        exit 1
      fi
      ;;
    -u|--url)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        DIVI_URL="$2"
        shift 2
      else
        echo -e "${RED}Error: Argument for $1 is missing${NC}" >&2
        exit 1
      fi
      ;;
    -c|--configmap)
      USE_CONFIGMAP=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    -*|--*=) # Unsupported flags
      echo -e "${RED}Error: Unsupported flag $1${NC}" >&2
      print_usage
      exit 1
      ;;
    *) # Unsupported positional arguments
      echo -e "${RED}Error: Unsupported argument $1${NC}" >&2
      print_usage
      exit 1
      ;;
  esac
done

# Check if either file or URL is provided
if [ -z "$DIVI_FILE" ] && [ -z "$DIVI_URL" ]; then
  echo -e "${RED}Error: You must provide either a Divi.zip file or a download URL${NC}" >&2
  print_usage
  exit 1
fi

# If file is provided, check if it exists and check its size
if [ -n "$DIVI_FILE" ]; then
  if [ ! -f "$DIVI_FILE" ]; then
    echo -e "${RED}Error: The specified file does not exist: $DIVI_FILE${NC}" >&2
    exit 1
  fi
  
  # Check file size (in MB)
  FILE_SIZE_MB=$(du -m "$DIVI_FILE" | cut -f1)
  echo -e "${BLUE}Divi.zip file size: ${FILE_SIZE_MB}MB${NC}"
  
  if [ "$FILE_SIZE_MB" -gt 100 ]; then
    echo -e "${YELLOW}Warning: Large file detected (${FILE_SIZE_MB}MB). This may require more memory.${NC}"
    echo -e "${YELLOW}If the job fails with OOM error, consider:${NC}"
    echo -e "  1. Using a direct download URL instead"
    echo -e "  2. Splitting the theme installation process"
    echo
    read -p "Continue with upload? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${RED}Upload canceled.${NC}"
      exit 1
    fi
  fi
fi

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delete any existing job and pod to ensure clean state
if [ "$USE_CONFIGMAP" = true ]; then
  JOB_NAME="wordpress-upload-divi-configmap"
else
  JOB_NAME="wordpress-upload-divi"
fi

echo -e "${BLUE}Cleaning up any existing jobs...${NC}"
kubectl delete job $JOB_NAME -n wordpress --ignore-not-found=true

# Apply job based on the chosen method
if [ "$USE_CONFIGMAP" = true ]; then
  echo -e "${YELLOW}Using ConfigMap-based job for Divi theme upload${NC}"
  
  # Apply ConfigMap and job
  echo -e "${BLUE}Applying ConfigMap and job...${NC}"
  kubectl apply -f "${SCRIPT_DIR}/upload-divi-theme-configmap.yaml"
  
  # If URL is provided, update the job YAML and apply
  if [ -n "$DIVI_URL" ]; then
    echo -e "${BLUE}Updating job with download URL...${NC}"
    sed "s|value: \"\"|value: \"$DIVI_URL\"|g" "${SCRIPT_DIR}/upload-divi-theme-job-configmap.yaml" | kubectl apply -f -
  else
    kubectl apply -f "${SCRIPT_DIR}/upload-divi-theme-job-configmap.yaml"
  fi
  
  # Get the pod name
  echo -e "${BLUE}Waiting for job pod to be created...${NC}"
  sleep 5
  POD_NAME=$(kubectl get pods -n wordpress -l job-name=wordpress-upload-divi-configmap -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
  
  # Wait for pod to be running
  COUNTER=0
  MAX_RETRIES=30  # Increased retries
  while [ -z "$POD_NAME" ] && [ $COUNTER -lt $MAX_RETRIES ]; do
    sleep 3
    COUNTER=$((COUNTER+1))
    POD_NAME=$(kubectl get pods -n wordpress -l job-name=wordpress-upload-divi-configmap -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    if [ $COUNTER -eq 10 ]; then
      echo -e "${YELLOW}Still waiting for pod creation...${NC}"
    fi
  done
  
  if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Error: Failed to get pod name after multiple retries${NC}" >&2
    echo -e "${YELLOW}Please check for issues with pod creation:${NC}"
    echo -e "  kubectl get pods -n wordpress"
    echo -e "  kubectl describe job/wordpress-upload-divi-configmap -n wordpress"
    exit 1
  fi
  
  echo -e "${GREEN}Pod created: $POD_NAME${NC}"
  
else
  echo -e "${YELLOW}Using basic job for Divi theme upload${NC}"
  
  # If URL is provided, update the job YAML and apply
  if [ -n "$DIVI_URL" ]; then
    echo -e "${BLUE}Updating job with download URL...${NC}"
    sed "s|value: \"\"|value: \"$DIVI_URL\"|g" "${SCRIPT_DIR}/upload-divi-theme-job.yaml" | kubectl apply -f -
  else
    kubectl apply -f "${SCRIPT_DIR}/upload-divi-theme-job.yaml"
  fi
  
  # Get the pod name
  echo -e "${BLUE}Waiting for job pod to be created...${NC}"
  sleep 5
  POD_NAME=$(kubectl get pods -n wordpress -l job-name=wordpress-upload-divi -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
  
  # Wait for pod to be running
  COUNTER=0
  MAX_RETRIES=30  # Increased retries
  while [ -z "$POD_NAME" ] && [ $COUNTER -lt $MAX_RETRIES ]; do
    sleep 3
    COUNTER=$((COUNTER+1))
    POD_NAME=$(kubectl get pods -n wordpress -l job-name=wordpress-upload-divi -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    if [ $COUNTER -eq 10 ]; then
      echo -e "${YELLOW}Still waiting for pod creation...${NC}"
    fi
  done
  
  if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Error: Failed to get pod name after multiple retries${NC}" >&2
    echo -e "${YELLOW}Please check for issues with pod creation:${NC}"
    echo -e "  kubectl get pods -n wordpress"
    echo -e "  kubectl describe job/wordpress-upload-divi -n wordpress"
    exit 1
  fi
  
  echo -e "${GREEN}Pod created: $POD_NAME${NC}"
fi

# Wait for pod to be running with a longer timeout
echo -e "${BLUE}Waiting for pod to be in Running state...${NC}"
kubectl wait --for=condition=Ready pod/$POD_NAME -n wordpress --timeout=120s
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Pod not ready yet, checking status...${NC}"
  kubectl describe pod/$POD_NAME -n wordpress
  echo -e "${YELLOW}Continuing anyway, but pod might not be fully ready${NC}"
fi

# If a file was provided, copy it to the pod
if [ -n "$DIVI_FILE" ]; then
  echo -e "${BLUE}Copying Divi.zip to the pod...${NC}"
  # Try copying with a timeout to avoid hanging
  timeout 300 kubectl cp "$DIVI_FILE" wordpress/$POD_NAME:/divi/Divi.zip
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to copy Divi.zip to the pod${NC}" >&2
    echo -e "${YELLOW}Possible reasons:${NC}"
    echo -e "  1. The pod might be in a bad state"
    echo -e "  2. The file might be too large for memory constraints"
    echo -e "  3. A network issue occurred during transfer"
    echo
    echo -e "${YELLOW}Checking pod status:${NC}"
    kubectl describe pod/$POD_NAME -n wordpress
    exit 1
  fi
  
  echo -e "${GREEN}File successfully copied to pod${NC}"
fi

# Follow the logs
echo -e "${BLUE}Following job logs...${NC}"
kubectl logs -f $POD_NAME -n wordpress || true

# Check job status
JOB_NAME=$(kubectl get pod $POD_NAME -n wordpress -o jsonpath="{.metadata.labels.job-name}" 2>/dev/null)
JOB_STATUS=$(kubectl get job $JOB_NAME -n wordpress -o jsonpath="{.status.conditions[?(@.type=='Complete')].status}" 2>/dev/null)

if [ "$JOB_STATUS" == "True" ]; then
  echo -e "${GREEN}Divi theme was successfully uploaded and installed!${NC}"
  echo -e "${YELLOW}Next steps:${NC}"
  echo -e "1. Log into your WordPress admin dashboard"
  echo -e "2. Navigate to Appearance > Themes"
  echo -e "3. Find the Divi theme and click 'Activate'"
else
  echo -e "${RED}Job did not complete successfully. Checking pod status:${NC}" >&2
  kubectl describe pod $POD_NAME -n wordpress
  exit 1
fi 