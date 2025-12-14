# Verify MySQL Exporter Configuration

## Check Environment Variables

On DEV1, verify your `.env` file has both variables:

```bash
cat .env | grep MYSQL
```

Should show:
```
MYSQL_HOST=192.168.1.100
MYSQL_MOAD_RO_USER=moad_ro
MYSQL_MOAD_RO_PASSWORD=your_password
```

## Test Connection String

The MySQL exporter uses this format:
```
${MYSQL_MOAD_RO_USER}:${MYSQL_MOAD_RO_PASSWORD}@tcp(${MYSQL_HOST}:3306)/
```

After substitution, it should look like:
```
moad_ro:ThruD@LookinGl@zz@tcp(192.168.1.100:3306)/
```

## Verify Environment Variable Substitution

Check if Docker Compose is substituting the variables:

```bash
# Check what the container sees
docker compose config | grep -A 3 mysqld-exporter
```

This will show the actual resolved values.

## Test MySQL Connection

Test if the MySQL server is reachable:

```bash
# From the container network
docker run --rm --network ss-moad_moad-network alpine ping -c 3 ${MYSQL_HOST}

# Test MySQL connection (replace with actual values from .env)
docker run --rm --network ss-moad_moad-network mysql:8.0 mysql -h ${MYSQL_HOST} -u ${MYSQL_MOAD_RO_USER} -p${MYSQL_MOAD_RO_PASSWORD} -e "SELECT 1"
```

## Common Issues

1. **MYSQL_HOST not set**: Add it to `.env` file
2. **Password has special characters**: May need URL encoding in connection string
3. **MySQL server not reachable**: Check network connectivity
4. **User doesn't exist**: Verify MySQL user (from `MYSQL_MOAD_RO_USER`) exists in MySQL

