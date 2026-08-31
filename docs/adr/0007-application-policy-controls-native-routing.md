# Application policy controls native routing

The Communications manager treats its Desired Pair as authoritative and treats OS routing only as the Observed Pair to verify. It configures each platform to minimize automatic rerouting and performs bounded Route convergence after every relevant native event, reporting failure instead of silently accepting a different Pair.
