set -e

# Add deployment scripts here

# Format:
# brownie run --network development-persistent scripts/deployment/deployment_script_name.py

brownie run --network development-persistent scripts/deployment/deploy_curve_handler.py
brownie run --network development-persistent scripts/deployment/deploy_curve_registry_cache.py
brownie run --network development-persistent scripts/deployment/deploy_chainlink_oracle.py

brownie run --network development-persistent scripts/deployment/deploy_conic_eth_pool.py
brownie run --network development-persistent scripts/deployment/deploy_eth_zap.py
