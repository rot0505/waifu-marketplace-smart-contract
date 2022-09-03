// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../old/ERC1155MarketplaceBase.sol";

contract ERC1155MarketplaceUpgrade is
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC1155MarketplaceBase
{
    using ArrayLibrary for address[];
    using ArrayLibrary for uint256[];

    function createSale(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 duration,
        uint256 amount
    ) external isProperContract(contractAddr) whenNotPaused {
        require(startPrice >= endPrice, "Invalid Sale Prices");
        _transferNFT(contractAddr, msg.sender, address(this), tokenId, amount);
        uint256 timestamp = block.timestamp;
        Sale memory sale = Sale(
            payment,
            msg.sender,
            startPrice,
            endPrice,
            amount,
            timestamp,
            duration,
            new address[](0),
            new uint256[](0),
            new uint256[](0)
        );
        if (tokenIdToSales[contractAddr][tokenId].length == 0) {
            saleTokenIds[contractAddr].push(tokenId);
        }
        tokenIdToSales[contractAddr][tokenId].push(sale);
        if (salesBySeller[msg.sender][contractAddr][tokenId].length == 0) {
            saleTokenIdsBySeller[msg.sender][contractAddr].push(tokenId);
        }
        salesBySeller[msg.sender][contractAddr][tokenId].push(sale);
        emit SaleCreated(
            contractAddr,
            tokenId,
            payment,
            startPrice,
            endPrice,
            amount,
            timestamp,
            duration
        );
    }

    function buy(
        address contractAddr,
        uint256 tokenId,
        address seller,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 amount,
        uint256 startedAt,
        uint256 duration
    )
        external
        payable
        isProperContract(contractAddr)
        nonReentrant
        whenNotPaused
    {
        SaleInfo memory sale = SaleInfo(
            seller,
            payment,
            startPrice,
            endPrice,
            amount,
            startedAt,
            duration
        );
        require(msg.sender != seller, "Caller Is Seller");
        uint256 price = getCurrentPrice(sale) * sale.amount;
        _buy(contractAddr, tokenId, sale, price);
        emit SaleSuccessful(contractAddr, tokenId, sale, price, msg.sender);
    }

    function cancelSale(
        address contractAddr,
        uint256 tokenId,
        address seller,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 amount,
        uint256 startedAt,
        uint256 duration
    ) external isProperContract(contractAddr) {
        SaleInfo memory sale = SaleInfo(
            seller,
            payment,
            startPrice,
            endPrice,
            amount,
            startedAt,
            duration
        );
        require(msg.sender == sale.seller, "Caller Is Not Seller");
        _transferNFT(contractAddr, address(this), msg.sender, tokenId, amount);
        _removeSale(contractAddr, tokenId, sale);
        emit SaleCancelled(contractAddr, tokenId, sale);
    }

    function makeOffer(
        address contractAddr,
        uint256 tokenId,
        address seller,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 startedAt,
        uint256 duration,
        uint256 price,
        uint256 amount
    ) external payable isProperContract(contractAddr) whenNotPaused {
        SaleInfo memory sale = SaleInfo(
            seller,
            payment,
            startPrice,
            endPrice,
            amount,
            startedAt,
            duration
        );
        _makeOffer(contractAddr, tokenId, sale, price, amount);
    }

    function cancelOffer(
        address contractAddr,
        uint256 tokenId,
        address seller,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 startedAt,
        uint256 duration,
        uint256 amount
    ) external isProperContract(contractAddr) {
        SaleInfo memory sale = SaleInfo(
            seller,
            payment,
            startPrice,
            endPrice,
            amount,
            startedAt,
            duration
        );
        require(msg.sender != seller, "Caller Is Not Buyer"); //onlyBuyer Modifier
        Sale[] storage sales = tokenIdToSales[contractAddr][tokenId];
        uint256 i = _findSaleIndex(sales, sale);
        _transferFund(
            sales[i].payment,
            sales[i].offerPrices[sales[i].offerers.findIndex(msg.sender)] *
                amount,
            msg.sender
        );
        _removeOffer(sales, sale, amount, msg.sender);
        sales = salesBySeller[seller][contractAddr][tokenId];
        i = _findSaleIndex(sales, sale);
        _removeOffer(sales, sale, amount, msg.sender);
        emit OfferCancelled(
            sales[i],
            contractAddr,
            tokenId,
            amount,
            msg.sender
        );
    }

    function acceptOffer(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 startedAt,
        uint256 duration,
        uint256 amount
    ) external isProperContract(contractAddr) whenNotPaused {
        SaleInfo memory sale = SaleInfo(
            msg.sender,
            payment,
            startPrice,
            endPrice,
            amount,
            startedAt,
            duration
        );
        _acceptOffer(contractAddr, tokenId, sale, amount);
    }

    function createAuction(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 amount
    ) external isProperContract(contractAddr) whenNotPaused {
        _transferNFT(contractAddr, msg.sender, address(this), tokenId, amount);
        Auction memory auction = Auction(
            payment,
            msg.sender,
            amount,
            block.timestamp,
            new address[](0),
            new uint256[](0),
            new uint256[](0)
        );
        if (tokenIdToAuctions[contractAddr][tokenId].length == 0) {
            auctionTokenIds[contractAddr].push(tokenId);
        }
        tokenIdToAuctions[contractAddr][tokenId].push(auction);
        if (auctionsBySeller[msg.sender][contractAddr][tokenId].length == 0) {
            auctionTokenIdsBySeller[msg.sender][contractAddr].push(tokenId);
        }
        auctionsBySeller[msg.sender][contractAddr][tokenId].push(auction);
        emit AuctionCreated(contractAddr, tokenId, payment, amount);
    }

    function cancelAuction(
        address contractAddr,
        uint256 tokenId,
        uint256 startedAt,
        uint256 amount
    ) external whenNotPaused {
        _transferNFT(contractAddr, address(this), msg.sender, tokenId, amount);
        _cancelAuction(contractAddr, tokenId, startedAt, amount);
        emit AuctionCancelled(contractAddr, tokenId, startedAt, amount);
    }

    function bid(
        address contractAddr,
        uint256 tokenId,
        address auctioneer,
        uint256 startedAt,
        uint256 bidAmount,
        uint256 bidPrice
    ) external payable whenNotPaused {
        require(msg.sender != auctioneer, "Auctioneer Cannot Bid");
        Auction[] storage auctions = tokenIdToAuctions[contractAddr][tokenId];
        uint256 i = _findAuctionIndex(auctions, auctioneer, startedAt);
        _escrowFund(auctions[i].payment, bidPrice * bidAmount);
        _bidAuction(auctions[i], bidPrice, bidAmount);
        auctions = auctionsBySeller[auctioneer][contractAddr][tokenId];
        i = _findAuctionIndex(auctions, auctioneer, startedAt);
        _bidAuction(auctions[i], bidPrice, bidAmount);
        emit AuctionBid(
            contractAddr,
            tokenId,
            auctioneer,
            startedAt,
            bidPrice,
            bidAmount
        );
    }

    function cancelBid(
        address contractAddr,
        uint256 tokenId,
        address auctioneer,
        uint256 startedAt,
        uint256 bidAmount
    ) external whenNotPaused {
        Auction[] storage auctions = tokenIdToAuctions[contractAddr][tokenId];
        uint256 i = _findAuctionIndex(auctions, auctioneer, startedAt);
        uint256 j = auctions[i].bidders.findIndex(msg.sender);
        uint256 price = auctions[i].bidPrices[j] * bidAmount;
        _transferFund(auctions[i].payment, price, msg.sender);
        _removeBid(auctions[i], msg.sender, bidAmount);
        auctions = auctionsBySeller[auctioneer][contractAddr][tokenId];
        i = _findAuctionIndex(auctions, auctioneer, startedAt);
        _removeBid(auctions[i], msg.sender, bidAmount);
        emit CancelBid(contractAddr, tokenId, auctioneer, startedAt, bidAmount);
    }

    function acceptBid(
        address contractAddr,
        uint256 tokenId,
        uint256 startedAt,
        uint256 bidAmount
    ) external payable whenNotPaused {
        Auction[] storage auctions = tokenIdToAuctions[contractAddr][tokenId];
        uint256 i = _findAuctionIndex(auctions, msg.sender, startedAt);
        Auction storage auction = auctions[i];
        require(auction.bidders.length > 0, "No Offer To Accept");
        i = auction.bidPrices.findMaxIndex();
        require(auction.bidAmounts[i] >= bidAmount, "Insuffcient Bid");
        address buyer = auction.bidders[i];
        _transferNFT(contractAddr, address(this), buyer, tokenId, bidAmount);
        uint256 price = auction.bidPrices[i];
        _payFund(
            auction.payment,
            price * bidAmount,
            msg.sender,
            contractAddr,
            tokenId
        );
        _removeBid(auction, buyer, bidAmount);
        auctions = auctionsBySeller[msg.sender][contractAddr][tokenId];
        i = _findAuctionIndex(auctions, msg.sender, startedAt);
        _removeBid(auctions[i], buyer, bidAmount);
        _cancelAuction(contractAddr, tokenId, startedAt, bidAmount);
        emit BidAccepted(contractAddr, tokenId, startedAt, price, bidAmount);
    }

    function isUpgraded() external pure returns (bool) {
        return true;
    }
}
