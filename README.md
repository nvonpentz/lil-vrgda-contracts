# Lil VRGDA contracts
A VRGDA implemetation for the Lil Nouns DAO  funded by prop 64. Live on Goerli at [lilsandbox.wtf](http://lilsandbox.wtf).

## Mainnet upgrade procedure
1. Deploy LilVRGDA contract and initialize, and transfer ownership to the DAO
1. Update the `minter` on the NounsToken contract to the LilVRGDA contract address with the `setMinter` function (requires on chain vote)
1. Call `unpause`  on the LilVRGDA contract (requires on chain vote)
