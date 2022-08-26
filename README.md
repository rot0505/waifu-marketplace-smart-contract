# NFT Marketplace Flow

```mermaid
classDiagram
  direction TB
  MarketplaceBase <|-- ERC721MarketplaceBase
  ERC721MarketplaceBase <|-- ERC721Marketplace
  Addresses <.. ERC721MarketplaceBase
  ERC721MarketplaceBase o-- Sale
  ERC721MarketplaceBase o-- Auction
  ERC721MarketplaceBase o-- Offer
  class ERC721Marketplace {
    +createSale(contractAddr, tokenId, payment, startPrice, endPrice, duration)
    +||payable|| buy(contractAddr, tokenId)
    +cancelSale(contractAddr, tokenId)
    +cancelSaleWhenPaused(contractAddr, tokenId)
    +||payable|| makeOffer(contractAddr, tokenId, price)
    +cancelOffer(contractAddr, tokenId)
    +acceptOffer(contractAddr, tokenId)
    +createAuction(contractAddr, tokenId, payment)
    +||payable|| bid(contractAddr, tokenId, price)
    +cancelBid(contractAddr, tokenId)
    +cancelAuction(contractAddr, tokenId)
    +acceptBid(contractAddr, tokenId)
  }
  class Sale {
    <<struct>>
    +address seller
    +uint8 payment
    +uint256 startPrice
    +uint256 endPrice
    +uint256 startedAt
    +uint256 duration
  }
  class Auction {
    <<struct>>
    +uint8 payment
    +address auctioneer
    +address[] bidders
    +uint256[] bidPrices
  }
  class Offer {
    <<struct>>
    +address offerer
    +uint256 offerPrice
  }
  class ERC721MarketplaceBase {
    <<abstract>>
    -map~address,uint256,Sale~ tokenIdToSales
    -map~address,uint256,Auction~ tokenIdToAuctions
    -map~address,uint256,Offer[]~ tokenIdToOffers
    -removeAt(offers, index)
    -_removeSale(contractAddr, tokenId)
    -_cancelAuction(contractAddr, tokenId)
    +getSale(contractAddr, tokenId) (Sale, Offer[], uint256)
    +getSales(contractAddr) (Sale[], Offer[][], uint256[])
    +getSalesBySeller(contractAddr, seller) (Sale[], Offer[][], uint256[])
    +getAuctions(contractAddr) Auction[]
    +getAuctionsBySeller(contractAddr, seller) Auction[]
    +getCurrentPrice(contractAddr, tokenId) uint256
    +||event|| SaleCreated(contractAddr, tokenId, payment, startPrice, endPrice, time, duration)
    +||event|| SaleSuccessful(contractAddr, tokenId, payment, price, buyer)
    +||event|| SaleCancelled(contractAddr, tokenId)
    +||event|| OfferCreated(contractAddr, tokenId, price, offerer)
    +||event|| OfferCancelled(contractAddr, tokenId, price, offerer)
    +||event|| OfferAccepted(contractAddr, tokenId, payment, price, offerer)
    +||event|| AuctionCreated(contractAddr, tokenId, payment, auctioneer)
    +||event|| AuctionCancelled(contractAddr, tokenId, auctioneer)
    +||event|| AuctionBid(contractAddr, tokenId, bidder, bidPrice)
    +||event|| BidAccepted(contractAddr, tokenId, payment, bidder, bidPrice)
    +||event|| CancelBid(contractAddr, tokenId, bidder)
    +||modifier|| onSale(contractAddr, tokenId)
    +||modifier|| onAuction(contractAddr, tokenId)
    +||modifier|| onlyAuctioneer(contractAddr, tokenId)
    +||modifier|| onlyBidder(contractAddr, tokenId)
  }
  class MarketplaceBase {
    <<abstract>>
    +address addressesContractAddr
    +address sparkTokenContractAddr
    -map~address,uint256[2]~ claimable
    -map~address,uint256[]~ saleTokenIds
    -map~address,uint256[]~ saleTokenIdsBySeller
    -map~address,uint256[]~ auctionTokenIds
    -map~address,uint256[]~ auctionTokenIdsBySeller
    -_escrowFund(payment, price)
    -_transferFund(payment, price, destination)
    -_payFund(payment, price, destination, contractAddr, tokenId)
    +setAddressesContractAddr(contractAddr)
    +setSparkTokenContractAddr(newSparkAddr)
    +getSaleTokens(contractAddr) uint256[]
    +getSaleTokensBySeller(contractAddr, seller) uint256[]
    +getClaimable(user, index) uint256[]
    +claim(amount, index)    
    +||modifier|| isProperContract(contractAddr)
  }
  class Addresses {
    -address[] normalContracts
    -address[] multiTokenContracts
    -map~address,bool~ verified
    -map~address,NFTType~ contractTypes
    +existingContract(contractAddr) bool
    +add(contractAddr)
    +getNFTType(contractAddr) NFTType
    +remove(contractAddr)
    +verify(contractAddr)
    +getNormalContracts() address[]
    +getMultiTokenContracts() address[]
    +getVerifiedNormalContracts() address[]
    +getVerifiedMultiTokenContracts() address[]
    +isVerified(contractAddr) bool
    +||modifier|| exists(contractAddr)
    +||modifier|| doesNotExist(contractAddr)
  }
```

```mermaid
sequenceDiagram
    participant User 1
    participant User 2
    participant Marketplace Owner
    participant Addresses
    participant ERC721Marketplace
    participant ERC721 NFT
    Marketplace Owner->>ERC721Marketplace: Set Addresses Smart Contract Address
    Marketplace Owner->>Addresses: Register NFT Smart Contract
    User 1->>ERC721 NFT: Approve NFT of tokenId to Marketplace
    Marketplace Owner->>Addresses: Verify NFT Smart Contract
    User 1->>ERC721Marketplace: Create/Cancel Sale with tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>ERC721 NFT: Transfer NFT of tokenId<br/>from User 1/Marketplace<br/>to Marketplace/User 1
    User 2->>ERC721Marketplace: Get Sale Tokens in ERC721 NFT Contract
    ERC721Marketplace-->>User 2: Sale Tokens in ERC721 NFT Contract
    User 2->>ERC721Marketplace: Get Sale Info of NFT of tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>User 2: Sale Info of NFT of tokenId in ERC721 NFT Contract
    User 2->>ERC721Marketplace: Purchase NFT of tokenId in ERC721 NFT Contract
    User 2-->>ERC721Marketplace: Escrow price of NFT of tokenId to Marketplace
    ERC721Marketplace-->>ERC721 NFT: Transfer NFT of tokenId<br/>from Marketplace<br/>to User 2
    ERC721Marketplace-->>User 1: Transfer coins of the price to User 1
    User 2->>ERC721Marketplace: Create Offer with tokenId in ERC721 NFT Contract
    User 2-->>ERC721Marketplace: Transfer offer price<br/>from User 2 to Marketplace
    User 2->>ERC721Marketplace: Cancel Offer with tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>User 2: Transfer offer price<br/>from Marketplace to User 2
    User 1->>ERC721Marketplace: Accept Highest Offer with tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>ERC721 NFT: Transfer NFT of tokenId<br/>from Marketplace to User 2
    ERC721Marketplace-->>User 1: Transfer offer price to User 1
    User 1->>ERC721Marketplace: Create/Cancel Auction with tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>ERC721 NFT: Transfer NFT of tokenId<br/>from User 1/Marketplace<br/>to Marketplace/User 1
    User 2->>ERC721Marketplace: Get Auction Tokens in ERC721 NFT Contract
    ERC721Marketplace-->>User 2: Auction Tokens in ERC721 NFT Contract
    User 2->>ERC721Marketplace: Get Auction Info of NFT of tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>User 2: Auction Info of NFT of tokenId in ERC721 NFT Contract
    User 2->>ERC721Marketplace: Create Bid with tokenId in ERC721 NFT Contract
    User 2-->>ERC721Marketplace: Transfer bid price<br/>from User 2 to Marketplace
    User 2->>ERC721Marketplace: Cancel Bid with tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>User 2: Transfer bid price<br/>from Marketplace to User 2
    User 1->>ERC721Marketplace: Accept Highest Bid with tokenId in ERC721 NFT Contract
    ERC721Marketplace-->>ERC721 NFT: Transfer NFT of tokenId<br/>from Marketplace to User 2
    ERC721Marketplace-->>User 1: Transfer bid price to User 1
```

# Smart Contract Project Setup and Test

This project is the NFT Marketplace Smart Contract integrating tools for unit test using Hardhat.

# Smart Contract Project Setup

Please install dependency modules
```shell
yarn
```

Please compile Smart Contracts
```shell
yarn compile
```

# Project Test

You can test Smart Contracts using
```shell
yarn test
```

# Deploy Smart Contracts

You can deploy Smart Contracts on the hardhat by
```shell
npx hardhat run scripts/deploy.js
```

First, you should change the .env.example file name as .env
Before deploying Smart contracts in the real networks like Ethereum or Rinkeby, you should add the chain info in the hardhat.config.js file

```javascript
{
  ...
  ropsten: {
    url: `https://ropsten.infura.io/v3/${process.env.INFURA_ID}`,
    tags: ["nft", "marketplace", "test"],
    chainId: 3,
    accounts: real_accounts,
    gas: 2100000,
    gasPrice: 8000000000
  },
  ...
}
```

You should add your wallet private key to .env file to make deploy transaction with your wallet

```javascript
...
PRIVATE_KEY=123123123123123
...
```

After that, you can deploy the Smart Contracts on the chain by

```shell
npx hardhat run scripts/deploy.js --network ropsten
```# waifu-marketplace-contract
