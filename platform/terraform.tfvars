root_id           = "kestrel"
root_display_name = "Kestrel Energy"
allowed_locations = ["westeurope", "germanywestcentral"]
logging_location  = "westeurope"

# One management group per application, below Corp or Online.
workloads = {
  corp   = {}
  online = {
    meter-readings = "Meter Readings"
  }
}

# Subscriptions are created by hand. Placing one here moves it into its management group.
subscriptions = {
  management   = ["cae14dc7-cfdc-49e7-868f-f054c31a9c6e"]
  connectivity = ["dfc79d96-ec2d-4f98-a8b1-b553e7c06376"]
  online-meter-readings = ["134d7b9d-5fe3-4754-b9d6-245b73c8eb0b"]
}

# Approved, expiring exceptions from Corp "No public endpoints".
exemptions = {}
