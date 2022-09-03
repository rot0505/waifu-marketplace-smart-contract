// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "./MarketplaceBase.sol";

abstract contract ERC1155MarketplaceBase is MarketplaceBase, ERC1155Receiver {
    using ArrayLibrary for address[];
    using ArrayLibrary for uint256[];

    struct Sale {
        uint8 payment;
        address seller;
        uint256 startPrice;
        uint256 endPrice;
        uint256 amount;
        uint256 startedAt;
        uint256 duration;
        address[] offerers;
        uint256[] offerPrices;
        uint256[] offerAmounts;
    }

    struct SaleInfo {
        address seller;
        uint8 payment;
        uint256 startPrice;
        uint256 endPrice;
        uint256 amount;
        uint256 startedAt;
        uint256 duration;
    }

    struct Auction {
        uint8 payment;
        address auctioneer;
        uint256 amount;
        uint256 startedAt;
        address[] bidders;
        uint256[] bidPrices;
        uint256[] bidAmounts;
    }

    struct AcceptBidReq {
        address contractAddr;
        uint256 tokenId;
        uint256 startedAt;
        uint256 bidAmount;
    }

    mapping(address => mapping(uint256 => Sale[])) internal tokenIdToSales;
    mapping(address => mapping(address => mapping(uint256 => Sale[])))
        internal salesBySeller;
    mapping(address => mapping(uint256 => Auction[]))
        internal tokenIdToAuctions;
    mapping(address => mapping(address => mapping(uint256 => Auction[])))
        internal auctionsBySeller;

    event SaleCreated(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 amount,
        uint256 time,
        uint256 duration
    );
    event SaleSuccessful(
        address contractAddr,
        uint256 tokenId,
        SaleInfo sale,
        uint256 price,
        address buyer
    );
    event SaleCancelled(address contractAddr, uint256 tokenId, SaleInfo sale);
    event OfferCreated(
        Sale sale,
        address contractAddr,
        uint256 tokenId,
        uint256 price,
        uint256 amount,
        address offerer
    );
    event OfferCancelled(
        Sale sale,
        address contractAddr,
        uint256 tokenId,
        uint256 amount,
        address offerer
    );
    event AuctionCreated(
        address contractAddr,
        uint256 tokenId,
        uint8 payment,
        uint256 amount
    );
    event AuctionCancelled(
        address contractAddr,
        uint256 tokenId,
        uint256 startedAt,
        uint256 amount
    );
    event AuctionBid(
        address contractAddr,
        uint256 tokenId,
        address auctioneer,
        uint256 startedAt,
        uint256 bidPrice,
        uint256 bidAmount
    );
    event CancelBid(
        address contractAddr,
        uint256 tokenId,
        address auctioneer,
        uint256 startedAt,
        uint256 bidAmount
    );
    event BidAccepted(
        address contractAddr,
        uint256 tokenId,
        uint256 startedAt,
        uint256 price,
        uint256 amount
    );

    function removeAt(Sale[] storage sales, uint256 index) internal {
        sales[index] = sales[sales.length - 1];
        sales.pop();
    }

    function removeAt(Auction[] storage auctions, uint256 index) internal {
        auctions[index] = auctions[auctions.length - 1];
        auctions.pop();
    }

    function _transferNFT(
        address contractAddr,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) internal {
        IERC1155(contractAddr).safeTransferFrom(from, to, tokenId, amount, "");
    }

    function _removeSale(
        address contractAddr,
        uint256 tokenId,
        SaleInfo memory sale
    ) internal {
        Sale[] storage sales = tokenIdToSales[contractAddr][tokenId];
        uint256[] storage tokenIds = saleTokenIds[contractAddr];
        _deleteSale(sales, tokenIds, sale, tokenId, true);
        sales = salesBySeller[sale.seller][contractAddr][tokenId];
        tokenIds = saleTokenIdsBySeller[sale.seller][contractAddr];
        _deleteSale(sales, tokenIds, sale, tokenId, false);
    }

    function _deleteSale(
        Sale[] storage sales,
        uint256[] storage tokenIds,
        SaleInfo memory sale,
        uint256 tokenId,
        bool fixClaim
    ) internal {
        uint256 i = _findSaleIndex(sales, sale);
        sales[i].amount -= sale.amount;
        uint256 length = sales[i].offerers.length;
        for (uint256 j; j < length; ++j) {
            if (sales[i].offerAmounts[j] > sales[i].amount) {
                if (fixClaim) {
                    _addClaimable(
                        sales[i].offerers[j],
                        sales[i].payment,
                        (sales[i].offerAmounts[j] - sales[i].amount) *
                            sales[i].offerPrices[j]
                    );
                }
                sales[i].offerAmounts[j] = sales[i].amount;
            }
        }
        if (sales[i].amount == 0) {
            removeAt(sales, i);
            tokenIds.remove(tokenId);
        }
    }

    function _getSaleInfo(Sale memory sale)
        internal
        pure
        returns (SaleInfo memory sl)
    {
        sl = SaleInfo(
            sale.seller,
            sale.payment,
            sale.startPrice,
            sale.endPrice,
            sale.amount,
            sale.startedAt,
            sale.duration
        );
    }

    function _isSameSale(Sale memory sale, SaleInfo memory saleInfo)
        internal
        pure
        returns (bool)
    {
        return
            sale.payment == saleInfo.payment &&
            sale.startPrice == saleInfo.startPrice &&
            sale.endPrice == saleInfo.endPrice &&
            sale.startedAt == saleInfo.startedAt &&
            sale.duration == saleInfo.duration &&
            sale.seller == saleInfo.seller;
    }

    function _removeOfferAt(Sale storage sale, uint256 index) internal {
        sale.offerers.removeAt(index);
        sale.offerPrices.removeAt(index);
        sale.offerAmounts.removeAt(index);
    }

    function _createOffer(
        Sale[] storage sales,
        SaleInfo memory sale,
        uint256 price,
        uint256 amount,
        uint256 curPrice
    ) internal {
        uint256 i = _findSaleIndex(sales, sale);
        require(sales[i].amount >= amount, "Insufficient Token On Sale");
        uint256 j = sales[i].offerers.findIndex(msg.sender);
        if (j < sales[i].offerers.length) {
            require(sales[i].offerPrices[j] == price, "Incorrect Offer Price");
            sales[i].offerAmounts[j] += amount;
        } else {
            require(price < curPrice, "Invalid Offer Price");
            sales[i].offerers.push(msg.sender);
            sales[i].offerPrices.push(price);
            sales[i].offerAmounts.push(amount);
        }
    }

    function _removeOffer(
        Sale[] storage sales,
        SaleInfo memory sale,
        uint256 amount,
        address offerer
    ) internal {
        uint256 i = _findSaleIndex(sales, sale);
        uint256 j = sales[i].offerers.findIndex(offerer);
        require(j < sales[i].offerers.length, "You Have No Offer");
        uint256 offerAmount = sales[i].offerAmounts[j];
        require(offerAmount >= amount, "Insufficient Offer To Cancel");
        sales[i].offerAmounts[j] -= amount;
        if (offerAmount == amount) {
            _removeOfferAt(sales[i], j);
        }
    }

    function _bidAuction(
        Auction storage auction,
        uint256 bidPrice,
        uint256 bidAmount
    ) internal {
        auction.bidders.push(msg.sender);
        auction.bidPrices.push(bidPrice);
        auction.bidAmounts.push(bidAmount);
    }

    function _removeBid(
        Auction storage auction,
        address bidder,
        uint256 bidAmount
    ) internal {
        uint256 i = auction.bidders.findIndex(bidder);
        require(i < auction.bidders.length, "No Bid");
        require(auction.bidAmounts[i] >= bidAmount, "Insufficient Bid");
        auction.bidAmounts[i] -= bidAmount;
        if (auction.bidAmounts[i] == 0) {
            auction.bidders.removeAt(i);
            auction.bidPrices.removeAt(i);
            auction.bidAmounts.removeAt(i);
        }
    }

    function _findSaleIndex(Sale[] memory sales, SaleInfo memory sale)
        internal
        pure
        returns (uint256 i)
    {
        uint256 length = sales.length;
        for (; i < length && !_isSameSale(sales[i], sale); ++i) {}
        require(i < length, "Not On Sale");
    }

    function _findAuctionIndex(
        Auction[] memory auctions,
        address auctioneer,
        uint256 startedAt
    ) internal pure returns (uint256 i) {
        uint256 length = auctions.length;
        for (
            ;
            i < length &&
                (auctions[i].auctioneer != auctioneer ||
                    auctions[i].startedAt != startedAt);
            ++i
        ) {}
        require(i < length, "No Auction");
    }

    function _removeAuction(
        Auction[] storage auctions,
        uint256[] storage tokenIds,
        uint256 tokenId,
        uint256 startedAt,
        uint256 amount,
        bool fixClaim
    ) internal {
        uint256 i = _findAuctionIndex(auctions, msg.sender, startedAt);
        uint256 length = auctions[i].bidders.length;
        require(auctions[i].amount >= amount, "Insufficient Token on Auction");
        auctions[i].amount -= amount;
        for (uint256 j; j < length; ++j) {
            if (auctions[i].bidAmounts[j] > auctions[i].amount) {
                uint256 removeAmount = auctions[i].bidAmounts[j] -
                    auctions[i].amount;
                if (fixClaim) {
                    _addClaimable(
                        auctions[i].bidders[j],
                        auctions[i].payment,
                        auctions[i].bidPrices[j] * removeAmount
                    );
                }
                _removeBid(auctions[i], auctions[i].bidders[j], removeAmount);
            }
        }
        if (auctions[i].amount == 0) {
            removeAt(auctions, i);
            if (auctions.length == 0) {
                tokenIds.remove(tokenId);
            }
        }
    }

    function _cancelAuction(
        address contractAddr,
        uint256 tokenId,
        uint256 startedAt,
        uint256 amount
    ) internal {
        Auction[] storage auctions = tokenIdToAuctions[contractAddr][tokenId];
        uint256[] storage tokenIds = auctionTokenIds[contractAddr];
        _removeAuction(auctions, tokenIds, tokenId, startedAt, amount, true);
        auctions = auctionsBySeller[msg.sender][contractAddr][tokenId];
        tokenIds = auctionTokenIdsBySeller[msg.sender][contractAddr];
        _removeAuction(auctions, tokenIds, tokenId, startedAt, amount, false);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function getSalesByNFT(address contractAddr, uint256 tokenId)
        external
        view
        isProperContract(contractAddr)
        returns (Sale[] memory sales, uint256[] memory currentPrices)
    {
        uint256 length = tokenIdToSales[contractAddr][tokenId].length;
        sales = new Sale[](length);
        currentPrices = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            sales[i] = tokenIdToSales[contractAddr][tokenId][i];
            currentPrices[i] = getCurrentPrice(_getSaleInfo(sales[i]));
        }
    }

    function getSalesBySellerNFT(
        address seller,
        address contractAddr,
        uint256 tokenId
    )
        external
        view
        isProperContract(contractAddr)
        returns (Sale[] memory sales, uint256[] memory currentPrices)
    {
        uint256 length = salesBySeller[seller][contractAddr][tokenId].length;
        sales = new Sale[](length);
        currentPrices = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            sales[i] = salesBySeller[seller][contractAddr][tokenId][i];
            currentPrices[i] = getCurrentPrice(_getSaleInfo(sales[i]));
        }
    }

    function getSale(
        address contractAddr,
        uint256 tokenId,
        address seller,
        uint8 payment,
        uint256 startPrice,
        uint256 endPrice,
        uint256 startedAt,
        uint256 duration,
        uint256 amount
    )
        external
        view
        isProperContract(contractAddr)
        returns (Sale memory sale, uint256 currentPrice)
    {
        return
            _getSale(
                contractAddr,
                tokenId,
                SaleInfo(
                    seller,
                    payment,
                    startPrice,
                    endPrice,
                    amount,
                    startedAt,
                    duration
                )
            );
    }

    function _getSale(
        address contractAddr,
        uint256 tokenId,
        SaleInfo memory sl
    ) internal view returns (Sale memory sale, uint256 currentPrice) {
        Sale[] storage sales = tokenIdToSales[contractAddr][tokenId];
        sale = sales[_findSaleIndex(sales, sl)];
        currentPrice = getCurrentPrice(sl);
    }

    function getSales(address contractAddr)
        external
        view
        isProperContract(contractAddr)
        returns (Sale[] memory sales, uint256[] memory currentPrices)
    {
        uint256 i;
        uint256 length;
        uint256[] storage tokenIds = saleTokenIds[contractAddr];
        uint256 saleLen = tokenIds.length;
        for (; i < saleLen; ++i) {
            length += tokenIdToSales[contractAddr][tokenIds[i]].length;
        }
        sales = new Sale[](length);
        currentPrices = new uint256[](length);
        length = 0;
        for (i = 0; i < saleLen; ++i) {
            uint256 len = tokenIdToSales[contractAddr][tokenIds[i]].length;
            for (uint256 j; j < len; ++j) {
                sales[length] = tokenIdToSales[contractAddr][tokenIds[i]][j];
                currentPrices[length] = getCurrentPrice(
                    _getSaleInfo(sales[length])
                );
                ++length;
            }
        }
    }

    function getSalesBySeller(address contractAddr, address owner)
        external
        view
        isProperContract(contractAddr)
        returns (Sale[] memory sales, uint256[] memory currentPrices)
    {
        uint256 i;
        uint256 length;
        uint256[] storage tokenIds = saleTokenIdsBySeller[owner][contractAddr];
        uint256 len = tokenIds.length;
        for (i; i < len; ++i) {
            length += salesBySeller[owner][contractAddr][tokenIds[i]].length;
        }
        sales = new Sale[](length);
        currentPrices = new uint256[](length);
        length = 0;
        for (i = 0; i < len; ++i) {
            Sale[] storage saleArr = salesBySeller[owner][contractAddr][
                tokenIds[i]
            ];
            uint256 saleLen = saleArr.length;
            for (uint256 j; j < saleLen; ++j) {
                sales[length] = saleArr[j];
                currentPrices[length] = getCurrentPrice(
                    _getSaleInfo(saleArr[j])
                );
                ++length;
            }
        }
    }

    function getAuctions(address contractAddr)
        external
        view
        isProperContract(contractAddr)
        returns (Auction[] memory auctions)
    {
        uint256 length;
        uint256 i;
        uint256[] storage tokenIds = auctionTokenIds[contractAddr];
        uint256 len = tokenIds.length;
        for (i; i < len; ++i) {
            length += tokenIdToAuctions[contractAddr][tokenIds[i]].length;
        }
        auctions = new Auction[](length);
        length = 0;
        for (i = 0; i < len; ++i) {
            Auction[] storage curAuctions = tokenIdToAuctions[contractAddr][
                tokenIds[i]
            ];
            uint256 curLen = curAuctions.length;
            for (uint256 j; j < curLen; ++j) {
                auctions[length++] = curAuctions[j];
            }
        }
    }

    function getAuctionsBySeller(address contractAddr, address owner)
        external
        view
        isProperContract(contractAddr)
        returns (Auction[] memory auctions)
    {
        uint256 length;
        uint256 i;
        uint256[] storage tokenIds = auctionTokenIdsBySeller[owner][
            contractAddr
        ];
        uint256 len = tokenIds.length;
        for (; i < len; ++i) {
            length += auctionsBySeller[owner][contractAddr][tokenIds[i]].length;
        }
        auctions = new Auction[](length);
        length = 0;
        for (i = 0; i < len; ++i) {
            Auction[] storage curAuctions = auctionsBySeller[owner][
                contractAddr
            ][tokenIds[i]];
            uint256 curLen = curAuctions.length;
            for (uint256 j; j < curLen; ++j) {
                auctions[length++] = curAuctions[j];
            }
        }
    }

    function getAuctionsByNFT(address contractAddr, uint256 tokenId)
        external
        view
        isProperContract(contractAddr)
        returns (Auction[] memory)
    {
        return tokenIdToAuctions[contractAddr][tokenId];
    }

    function getAuctionsBySellerNFT(
        address seller,
        address contractAddr,
        uint256 tokenId
    ) external view isProperContract(contractAddr) returns (Auction[] memory) {
        return auctionsBySeller[seller][contractAddr][tokenId];
    }

    function getCurrentPrice(SaleInfo memory sale)
        public
        view
        returns (uint256)
    {
        return
            block.timestamp >= sale.startedAt + sale.duration
                ? sale.endPrice
                : (sale.startPrice -
                    ((sale.startPrice - sale.endPrice) *
                        (block.timestamp - sale.startedAt)) /
                    sale.duration);
    }

    function _buy(
        address contractAddr,
        uint256 tokenId,
        SaleInfo memory sale,
        uint256 price
    ) internal {
        _escrowFund(sale.payment, price);
        _payFund(sale.payment, price, sale.seller, contractAddr, tokenId);
        uint256 amount = sale.amount;
        _transferNFT(contractAddr, address(this), msg.sender, tokenId, amount);
        _removeSale(contractAddr, tokenId, sale);
    }

    function _makeOffer(
        address contractAddr,
        uint256 tokenId,
        SaleInfo memory sale,
        uint256 price,
        uint256 amount
    ) internal {
        require(msg.sender != sale.seller, "Caller Is Not Buyer");
        uint256 curPrice = getCurrentPrice(sale);
        _escrowFund(sale.payment, price * amount);
        Sale[] storage sales = tokenIdToSales[contractAddr][tokenId];
        _createOffer(sales, sale, price, amount, curPrice);
        sales = salesBySeller[sale.seller][contractAddr][tokenId];
        _createOffer(sales, sale, price, amount, curPrice);
    }

    function _acceptOffer(
        address contractAddr,
        uint256 tokenId,
        SaleInfo memory sale,
        uint256 amount
    ) internal {
        require(msg.sender == sale.seller, "Caller Is Not Seller");
        Sale[] storage sales = tokenIdToSales[contractAddr][tokenId];
        uint256 i = _findSaleIndex(sales, sale);
        require(i < sales.length, "Not On Sale");
        require(sales[i].amount >= amount, "Insufficient Sale For Offer");
        require(sales[i].offerers.length > 0, "No Offer on the Sale");
        uint256 maxOffererId = sales[i].offerPrices.findMaxIndex();
        uint256 offerAmount = sales[i].offerAmounts[maxOffererId];
        require(offerAmount >= amount, "Insufficient Offer To Accept");
        uint256 price = sales[i].offerPrices[maxOffererId] * amount;
        _payFund(sale.payment, price, msg.sender, contractAddr, tokenId);
        address buyer = sales[i].offerers[maxOffererId];
        _transferNFT(contractAddr, address(this), buyer, tokenId, amount);
        _removeOffer(sales, sale, amount, buyer);
        sales = salesBySeller[msg.sender][contractAddr][tokenId];
        _removeOffer(sales, sale, amount, buyer);
        _removeSale(contractAddr, tokenId, sale);
        emit SaleSuccessful(contractAddr, tokenId, sale, price, buyer);
    }
}
