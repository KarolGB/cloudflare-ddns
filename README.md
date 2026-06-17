# cloudflare-ddns-script

## System requirements
- jq
- curl
- git
```
apt install curl && apt install jq
```


## Cloudflare requirements
- cloudflare_api_token
- zone_identifier
- User email

## Create API Token in cloudflare

In this page: [Cloudflare api Dashboard](https://dash.cloudflare.com/profile/api-tokens)

Create a custom token with the next privileges

<img width="909" height="254" alt="image" src="https://github.com/user-attachments/assets/130cb126-bb21-4aa8-85ef-02c3545d84de" />


## Installation

```
git clone https://github.com/KarolGB/cloudflare-ddns.git
```

Once is clone modify the files in .secrets with your token, zone_id and email

## Cron automation

```
crontab -e
```

### Cron example

Run every minute

```
* * * * * /path/to/the/script.sh
```

Run Every Hour

```
0 * * * * /path/to/the/script.sh
```

Run once an Day

```
0 0 * * * /path/to/the/script.sh
```
