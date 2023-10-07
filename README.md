## Description
The DSCEngine contract is a foundational building block of the Dsce stablecoin system. Dsce is a decentralized and algorithmically stable cryptocurrency with a unique combination of characteristics, including exogenous collateral, a dollar peg, and a focus on maintaining a health factor above a minimum threshold.

At its core, DSCEngine manages the deposit and withdrawal of collateral assets, as well as the minting and burning of DSC stablecoins. It leverages a variety of external smart contracts and interfaces to achieve its goals. These include the DecentralizedStableCoin contract, which represents the DSC token itself, and the ReentrancyGuard contract for security.

One of the central concepts in the DSCEngine contract is the "health factor." The health factor measures the safety of the system by comparing the total collateral value to the total amount of DSC tokens minted. If the health factor falls below a certain threshold, it becomes possible for the system to be liquidated. Liquidation involves users redeeming collateral assets in exchange for DSC tokens to restore the system's health.

Users can interact with DSCEngine through various external and public functions. They can deposit collateral assets, mint DSC tokens, redeem collateral, and even participate in the liquidation of undercollateralized accounts. Additionally, the contract provides functions for calculating collateral values, checking health factors, and managing DSC balances.

One unique feature of the system is the ability to deposit collateral and mint DSC tokens in a single transaction, simplifying the user experience. Furthermore, the contract incentivizes liquidators by offering a 10% bonus on collateral assets obtained during the liquidation process.
 DSCEngine plays a critical role in maintaining the stability and integrity of the Dsce stablecoin system. It provides a mechanism for users to interact with the system securely while ensuring that the value of DSC tokens remains anchored to the US dollar through the collateralization of assets. This decentralized and algorithmically stablecoin system aims to offer users a reliable and transparent cryptocurrency option within the blockchain ecosystem.

## Getting Started
## Requirements
### git
   ## You'll know you did it right if you can run 
     git --version 
 and you see a response like git version x.x.x
### foundry
 ## You'll know you did it right if you can run 
    forge --version 
 and you see a response like forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)

### Quickstart
    git clone https://github.com/bennymunyiri/foundry-defi-stablecoin
    cd foundry-defi-stablecoin-f23 
    forge build
## Usage
### Start a local node
    make anvil
## Deploy
This will default to your local node. You need to have it running in another terminal in order for it to deploy.

    make deploy

## Deployment to a testnet or mainnet
Setup environment variables
You'll want to set your SEPOLIA_RPC_URL and PRIVATE_KEY as environment variables. You can add them to a .env file, similar to what you see in .env.example.

PRIVATE_KEY: The private key of your account (like from metamask). NOTE: FOR DEVELOPMENT, PLEASE USE A KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
You can learn how to export it here.
SEPOLIA_RPC_URL: This is url of the sepolia testnet node you're working with. You can get setup with one for free from Alchemy
Optionally, add your ETHERSCAN_API_KEY if you want to verify your contract on Etherscan.

## Get testnet ETH
Head over to faucets.chain.link and get some testnet ETH. You should see the ETH show up in your metamask.

## Deploy
make deploy ARGS="--network sepolia"
