#!/bin/bash

# Install PostgreSQL
echo "Installing PostgreSQL..."
yay -S --noconfirm --needed postgresql

# Check if data directory already exists and is initialized. The probe has to
# run as root: /var/lib/postgres is 0700 postgres-owned, so an unprivileged
# `ls -A` fails, returns nothing, and reads as "empty" -- which sent every
# re-run into initdb only for it to refuse with "exists but is not empty".
# PG_VERSION is written by initdb, so it marks a complete cluster.
if ! sudo test -s /var/lib/postgres/data/PG_VERSION; then
    echo "Initializing PostgreSQL database..."
    sudo -u postgres initdb -D /var/lib/postgres/data --locale=C.UTF-8 --encoding=UTF8 --data-checksums
else
    echo "PostgreSQL data directory already initialized, skipping..."
fi

# Start and enable PostgreSQL service
echo "Starting PostgreSQL service..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Wait for PostgreSQL to be ready
sleep 2

# Create a database user matching the current user if it doesn't exist
echo "Setting up PostgreSQL user..."
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_user WHERE usename='$USER'" | grep -q 1; then
    sudo -u postgres createuser --interactive -d "$USER"
    echo "Created PostgreSQL user: $USER"
else
    echo "PostgreSQL user $USER already exists"
fi

# Create a default database for the user if it doesn't exist
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$USER"; then
    createdb "$USER"
    echo "Created default database: $USER"
else
    echo "Database $USER already exists"
fi

echo "PostgreSQL installation and setup complete!"
echo "You can now connect to PostgreSQL using: psql"