// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./MarketplaceBase.sol";

abstract contract ERC721MarketplaceBase is MarketplaceBase {
    using ArrayLibrary for uint256[];

    struct Sale {
        address seller;
        uint8 payment;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startedAt;
        uint256 duration;
    }

    struct Auction {
        uint8 payment;
        address auctioneer;
        address[] bidders;
        uint256[] bidPrices;
    }

    struct Offer {
        address offerer;
        uint256 offerPrice;
    }

    mapping(address => mapping(uint256 => Sale)) internal tokenIdToSales;
    mapping(address => mapping(uint256 => Offer[])) internal tokenIdToOffers;
    mapping(address => mapping(uint256 => Auction)) internal tokenIdToAuctions;

    event SaleCreated(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 time,
        uint256 duration
    );
    event SaleSuccessful(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 price,
        address buyer
    );
    event SaleCancelled(address contractAddr, uint256 tokenId);
    event OfferCreated(
        address contractAddr,
        uint256 tokenId,
        uint256 price,
        address offerer
    );
    event OfferCancelled(
        address contractAddr,
        uint256 tokenId,
        uint256 price,
        address offerer
    );
    event OfferAccepted(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 price,
        address offerer
    );
    event AuctionCreated(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        address auctioneer
    );
    event AuctionCancelled(
        address contractAddr,
        uint256 tokenId,
        address auctioneer
    );
    event AuctionBid(
        address contractAddr,
        uint256 tokenId,
        address bidder,
        uint256 bidPrice
    );
    event BidAccepted(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        address bidder,
        uint256 bidPrice
    );
    event CancelBid(address contractAddr, uint256 tokenId, address bidder);

    function removeAt(Offer[] storage offers, uint256 index) internal {
        offers[index] = offers[offers.length - 1];
        offers.pop();
    }

    function _removeSale(address contractAddr, uint256 tokenId) internal {
        saleTokenIds[contractAddr].remove(tokenId);
        Sale memory sale = tokenIdToSales[contractAddr][tokenId];
        saleTokenIdsBySeller[sale.seller][contractAddr].remove(tokenId);
        Offer[] storage offers = tokenIdToOffers[contractAddr][tokenId];
        for (uint256 i; i < offers.length; ++i) {
            _addClaimable(
                offers[i].offerer,
                sale.payment,
                offers[i].offerPrice
            );
        }
        delete tokenIdToOffers[contractAddr][tokenId];
        delete tokenIdToSales[contractAddr][tokenId];
    }

    function _cancelAuction(address contractAddr, uint256 tokenId) internal {
        Auction memory auction = tokenIdToAuctions[contractAddr][tokenId];
        for (uint256 i; i < auction.bidders.length; ++i) {
            _addClaimable(
                auction.bidders[i],
                auction.payment,
                auction.bidPrices[i]
            );
        }
        delete tokenIdToAuctions[contractAddr][tokenId];
        auctionTokenIds[contractAddr].remove(tokenId);
        auctionTokenIdsBySeller[msg.sender][contractAddr].remove(tokenId);
    }

    function getSale(address contractAddr, uint256 tokenId)
        external
        view
        isProperContract(contractAddr)
        returns (
            Sale memory sale,
            Offer[] memory offers,
            uint256 currentPrice
        )
    {
        sale = tokenIdToSales[contractAddr][tokenId];
        require(sale.startPrice > 0, "Not On Sale");
        offers = tokenIdToOffers[contractAddr][tokenId];
        currentPrice = getCurrentPrice(contractAddr, tokenId);
    }

    function getSales(address contractAddr)
        external
        view
        isProperContract(contractAddr)
        returns (
            Sale[] memory sales,
            Offer[][] memory offers,
            uint256[] memory currentPrices
        )
    {
        uint256 length = saleTokenIds[contractAddr].length;
        sales = new Sale[](length);
        offers = new Offer[][](length);
        currentPrices = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = saleTokenIds[contractAddr][i];
            sales[i] = tokenIdToSales[contractAddr][tokenId];
            offers[i] = tokenIdToOffers[contractAddr][tokenId];
            currentPrices[i] = getCurrentPrice(contractAddr, tokenId);
        }
    }

    function getSalesBySeller(address contractAddr, address seller)
        external
        view
        isProperContract(contractAddr)
        returns (
            Sale[] memory sales,
            Offer[][] memory offers,
            uint256[] memory currentPrices
        )
    {
        uint256 length = saleTokenIdsBySeller[seller][contractAddr].length;
        sales = new Sale[](length);
        offers = new Offer[][](length);
        currentPrices = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = saleTokenIdsBySeller[seller][contractAddr][i];
            sales[i] = tokenIdToSales[contractAddr][tokenId];
            offers[i] = tokenIdToOffers[contractAddr][tokenId];
            currentPrices[i] = getCurrentPrice(contractAddr, tokenId);
        }
    }

    function getAuctions(address contractAddr)
        external
        view
        isProperContract(contractAddr)
        returns (Auction[] memory auctions)
    {
        uint256 length = auctionTokenIds[contractAddr].length;
        auctions = new Auction[](length);
        for (uint256 i; i < length; ++i) {
            auctions[i] = tokenIdToAuctions[contractAddr][
                auctionTokenIds[contractAddr][i]
            ];
        }
    }

    function getAuctionsBySeller(address contractAddr, address seller)
        external
        view
        isProperContract(contractAddr)
        returns (Auction[] memory auctions)
    {
        uint256 length = auctionTokenIdsBySeller[seller][contractAddr].length;
        auctions = new Auction[](length);
        for (uint256 i; i < length; ++i) {
            auctions[i] = tokenIdToAuctions[contractAddr][
                auctionTokenIdsBySeller[seller][contractAddr][i]
            ];
        }
    }

    function getCurrentPrice(address contractAddr, uint256 tokenId)
        public
        view
        isProperContract(contractAddr)
        returns (uint256)
    {
        Sale memory sale = tokenIdToSales[contractAddr][tokenId];
        require(sale.startPrice > 0, "Not On Sale");
        uint256 timestamp = block.timestamp;
        if (timestamp >= sale.startedAt + sale.duration) {
            return sale.endPrice;
        }
        return
            sale.startPrice -
            ((sale.startPrice - sale.endPrice) * (timestamp - sale.startedAt)) /
            sale.duration;
    }
}
