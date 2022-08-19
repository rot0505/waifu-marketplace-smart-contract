// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ClockSaleBase.sol";

contract ClockSale is ClockSaleBase, Ownable {
    function createSale(
        address contractAddr,
        uint256 _tokenId,
        string memory payment,
        uint256 price
    ) external virtual exists(contractAddr) verified(contractAddr) {
        require(price == uint256(uint128(price)), "Price not valid");
        _escrow(contractAddr, msg.sender, _tokenId);
        Sale memory sale = Sale(
            msg.sender,
            payment,
            uint128(price),
            block.timestamp
        );
        _addSale(contractAddr, _tokenId, sale);
    }

    function createAuction(
        address contractAddr,
        uint256 _tokenId,
        string memory payment,
        uint256 price,
        uint256 duration
    ) external virtual exists(contractAddr) verified(contractAddr) {
        require(price == uint256(uint128(price)), "Price not valid");

        _escrow(contractAddr, msg.sender, _tokenId);
        Auction memory auction = Auction(
            msg.sender,
            payment,
            uint128(price),
            duration,
            block.timestamp
        );
        _addAuction(contractAddr, _tokenId, auction);
    }

    function buy(
        address contractAddr,
        uint256 tokenId,
        uint256 amount
    )
        external
        payable
        virtual
        exists(contractAddr)
        onSale(contractAddr, tokenId)
        onlyBuyer(contractAddr, tokenId)
    {
        _buy(contractAddr, tokenId, msg.sender, amount);
        _transfer(contractAddr, msg.sender, tokenId);
    }

    function cancelSale(address contractAddr, uint256 _tokenId)
        external
        exists(contractAddr)
        onSale(contractAddr, _tokenId)
        onlySeller(contractAddr, _tokenId)
    {
        _cancelSale(contractAddr, _tokenId);
    }

    function cancelAuction(address contractAddr, uint256 _tokenId)
        external
        exists(contractAddr)
        onAuction(contractAddr, _tokenId)
        onlyAuctioneer(contractAddr, _tokenId)
    {
        _cancelAuction(contractAddr, _tokenId);
    }

    function getCurrentPrice(address contractAddr, uint256 _tokenId)
        external
        view
        exists(contractAddr)
        onSale(contractAddr, _tokenId)
        returns (uint256)
    {
        return tokenIdToSales[contractAddr][_tokenId].price;
    }

    function transfer(
        address contractAddr,
        address _receiver,
        uint256 _tokenId
    ) external virtual exists(contractAddr) {
        _send(contractAddr, msg.sender, _receiver, _tokenId);
    }

    function createOffer(
        address contractAddr,
        uint256 tokenId,
        string memory payment,
        uint256 amount
    )
        external
        payable
        exists(contractAddr)
        onSale(contractAddr, tokenId)
        onlyBuyer(contractAddr, tokenId)
        hasNoOffer(contractAddr, tokenId)
    {
        require(
            amount < tokenIdToSales[contractAddr][tokenId].price,
            "Price should be lower"
        );
        _transferIncludeFee(msg.sender, address(this), payment, amount, false);
        _createOffer(contractAddr, tokenId, msg.sender, payment, amount);
    }

    function bid(
        address contractAddr,
        uint256 tokenId,
        string memory payment,
        uint256 amount
    )
        external
        payable
        exists(contractAddr)
        onAuction(contractAddr, tokenId)
        onlyBidder(contractAddr, tokenId)
        hasNoBid(contractAddr, tokenId)
    {
        require(
            block.timestamp <=
                tokenIdToAuctions[contractAddr][tokenId].startedAt +
                    tokenIdToAuctions[contractAddr][tokenId].duration,
            "Auction is already finished"
        );
        require(
            amount > tokenIdToAuctions[contractAddr][tokenId].price,
            "Bid in current price range"
        );
        uint256 bidLength = bids[contractAddr][tokenId].length;
        require(
            bidLength == 0 ||
                bids[contractAddr][tokenId][bidLength - 1].price < amount,
            "You should bid on higher price"
        );
        _transferIncludeFee(msg.sender, address(this), payment, amount, false);
        _bid(contractAddr, tokenId, msg.sender, payment, amount);
    }

    function getOffers(address contractAddr, uint256 tokenId)
        external
        view
        exists(contractAddr)
        onSale(contractAddr, tokenId)
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 length = offers[contractAddr][tokenId].length;
        address[] memory offerers = new address[](length);
        uint256[] memory prices = new uint256[](length);
        uint256[] memory times = new uint256[](length);
        uint256 i;
        for (i = 0; i < length; ++i) {
            offerers[i] = offers[contractAddr][tokenId][i].offerer;
            prices[i] = offers[contractAddr][tokenId][i].price;
            times[i] = offers[contractAddr][tokenId][i].time;
        }
        return (offerers, prices, times);
    }

    function getBids(address contractAddr, uint256 tokenId)
        external
        view
        exists(contractAddr)
        onAuction(contractAddr, tokenId)
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 length = bids[contractAddr][tokenId].length;
        address[] memory bidders = new address[](length);
        uint256[] memory prices = new uint256[](length);
        uint256[] memory times = new uint256[](length);
        uint256 i;
        for (i = 0; i < length; ++i) {
            bidders[i] = bids[contractAddr][tokenId][i].bidder;
            prices[i] = bids[contractAddr][tokenId][i].price;
            times[i] = bids[contractAddr][tokenId][i].time;
        }
        return (bidders, prices, times);
    }

    function cancelOffer(address contractAddr, uint256 tokenId)
        external
        exists(contractAddr)
        onSale(contractAddr, tokenId)
        hasOffer(contractAddr, tokenId)
    {
        uint256 length = offers[contractAddr][tokenId].length;
        uint256 i;
        for (
            i = 0;
            i < length &&
                offers[contractAddr][tokenId][i].offerer != msg.sender;
            ++i
        ) {}
        require(i < length, "You haven't got offer");
        _transferIncludeFee(
            address(this),
            msg.sender,
            offers[contractAddr][tokenId][i].payment,
            offers[contractAddr][tokenId][i].price,
            false
        );
        for (; i < length - 1; ++i) {
            offers[contractAddr][tokenId][i] = offers[contractAddr][tokenId][
                i + 1
            ];
        }
        offers[contractAddr][tokenId].pop();
    }

    function cancelBid(address contractAddr, uint256 tokenId)
        external
        exists(contractAddr)
        onAuction(contractAddr, tokenId)
        hasBid(contractAddr, tokenId)
    {
        uint256 length = bids[contractAddr][tokenId].length;
        uint256 i;
        for (
            i = 0;
            i < length && bids[contractAddr][tokenId][i].bidder != msg.sender;
            ++i
        ) {}
        require(i < length, "You haven't got bid");
        _transferIncludeFee(
            address(this),
            msg.sender,
            bids[contractAddr][tokenId][i].payment,
            bids[contractAddr][tokenId][i].price,
            false
        );
        for (; i < length - 1; ++i) {
            bids[contractAddr][tokenId][i] = bids[contractAddr][tokenId][i + 1];
        }
        bids[contractAddr][tokenId].pop();
    }

    function setAddressesContractAddr(address contractAddr) external onlyOwner {
        addressesContractAddr = contractAddr;
    }

    function setFeeAddress(address feeAddr) external onlyOwner {
        feeAddress = feeAddr;
    }

    function setFeePercent(string memory token, uint256 fee)
        external
        onlyOwner
    {
        feePercent[token] = fee;
    }
}
