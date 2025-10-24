echo "----------------------------------------"
echo " Running post-install validation checks "
echo "----------------------------------------"

# Check Docker installation
if ! command -v docker &> /dev/null; then
  echo "❌ Docker is not installed or not in PATH."
  exit 1
else
  echo "✅ Docker command found."
fi

# Check Docker service
if ! systemctl is-active --quiet docker; then
  echo "❌ Docker service is not running."
  exit 1
else
  echo "✅ Docker service is running."
fi

# Check Docker Compose installation
if ! command -v docker-compose &> /dev/null; then
  echo "❌ docker-compose not found."
  exit 1
else
  echo "✅ docker-compose command found."
fi

# Verify that the expected containers are running
expected_containers=("postgres" "grafana" "etl_service")
for container in "${expected_containers[@]}"; do
  if [ "$(docker ps --filter "name=${container}" --filter "status=running" -q)" ]; then
    echo "✅ Container '${container}' is running."
  else
    echo "❌ Container '${container}' is NOT running."
  fi
done

# Check container health (if healthchecks defined)
echo "----------------------------------------"
echo "Container health status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Optional: test PostgreSQL connectivity
if docker exec -it postgres psql -U postgres -c '\l' > /dev/null 2>&1; then
  echo "✅ PostgreSQL is responding."
else
  echo "❌ PostgreSQL connection test failed."
fi

# Optional: test Grafana port (defaults to 3000)
if curl -fs http://localhost:3000/api/health > /dev/null 2>&1; then
  echo "✅ Grafana is responding on port 3000."
else
  echo "⚠️ Grafana did not respond on port 3000."
fi

echo "----------------------------------------"
echo " Post-install validation complete."
echo " Review above results before proceeding. "
echo "----------------------------------------"
