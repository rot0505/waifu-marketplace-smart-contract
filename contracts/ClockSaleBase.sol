// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface AddressesInterface {
    function existingContract(address contractAddr)
        external
        view
        returns (bool);

    function isVerified(address contractAddr) external view returns (bool);
}

/// @title Sale Core
/// @dev Contains models, variables, and internal methods for the sale.
/// @notice We omit a fallback function to prevent accidental sends to this contract.
contract ClockSaleBase {
    // Represents an sale on an NFT
    struct Sale {
        // Address of Smart Contract
        // address contractAddr;
        // Current owner of NFT
        address seller;
        // Payment token address
        string payment;
        // Price (in wei) at beginning of sale
        uint128 price;
        uint256 startedAt;
    }

    struct Auction {
        address auctioneer;
        string payment;
        uint128 price;
        uint256 duration;
        uint256 startedAt;
    }

    struct Offer {
        // Address of Offerer
        address offerer;
        string payment;
        // Offering price
        uint256 price;
        uint256 time;
    }

    struct Bid {
        // Address of Offerer
        address bidder;
        string payment;
        // Offering price
        uint256 price;
        uint256 time;
    }

    // Map from token ID to their corresponding sale.
    mapping(address => mapping(uint256 => Sale)) public tokenIdToSales;
    mapping(address => mapping(uint256 => Auction)) public tokenIdToAuctions;

    // Save Sale Token Ids by Contract Addresses
    mapping(address => uint256[]) public saleTokenIds;
    mapping(address => uint256[]) public auctionTokenIds;
    // Sale Token Ids by Seller Addresses
    mapping(address => mapping(address => uint256[]))
        private saleTokenIdsBySeller;
    mapping(address => mapping(address => uint256[]))
        private auctionTokenIdsBySeller;
    // Offers
    mapping(address => mapping(uint256 => Offer[])) public offers;
    mapping(address => mapping(uint256 => Bid[])) public bids;
    mapping(string => uint256) public feePercent;
    address public addressesContractAddr;
    address public feeAddress;

    modifier onSale(address contractAddr, uint256 tokenId) {
        require(tokenIdToSales[contractAddr][tokenId].price > 0, "Not On Sale");
        _;
    }

    modifier notOnSale(address contractAddr, uint256 tokenId) {
        require(
            tokenIdToSales[contractAddr][tokenId].price == 0,
            "Already On Sale"
        );
        _;
    }

    modifier onAuction(address contractAddr, uint256 tokenId) {
        require(
            tokenIdToAuctions[contractAddr][tokenId].price > 0,
            "Not On Auction"
        );
        _;
    }

    modifier notOnAuction(address contractAddr, uint256 tokenId) {
        require(
            tokenIdToAuctions[contractAddr][tokenId].price == 0,
            "Already On Auction"
        );
        _;
    }

    modifier onlySeller(address contractAddr, uint256 tokenId) {
        require(
            tokenIdToSales[contractAddr][tokenId].seller == msg.sender,
            "Caller is not seller"
        );
        _;
    }

    modifier onlyBuyer(address contractAddr, uint256 tokenId) {
        require(
            tokenIdToSales[contractAddr][tokenId].seller != msg.sender,
            "Caller is seller"
        );
        _;
    }

    modifier onlyAuctioneer(address contractAddr, uint256 tokenId) {
        require(
            tokenIdToAuctions[contractAddr][tokenId].auctioneer == msg.sender,
            "Caller is not auctioneer"
        );
        _;
    }

    modifier onlyBidder(address contractAddr, uint256 tokenId) {
        require(
            tokenIdToAuctions[contractAddr][tokenId].auctioneer != msg.sender,
            "Caller is auctioneer"
        );
        _;
    }

    modifier hasOffer(address contractAddr, uint256 tokenId) {
        require(
            _hasOffer(contractAddr, tokenId, msg.sender) == true,
            "You haven't got any offer"
        );
        _;
    }

    modifier hasNoOffer(address contractAddr, uint256 tokenId) {
        require(
            _hasOffer(contractAddr, tokenId, msg.sender) == false,
            "You already have offer"
        );
        _;
    }

    modifier hasBid(address contractAddr, uint256 tokenId) {
        require(
            _hasBid(contractAddr, tokenId, msg.sender) == true,
            "You haven't got any offer"
        );
        _;
    }

    modifier hasNoBid(address contractAddr, uint256 tokenId) {
        require(
            _hasBid(contractAddr, tokenId, msg.sender) == false,
            "You already have offer"
        );
        _;
    }

    modifier exists(address contractAddr) {
        require(
            addressesContractAddr != address(0),
            "Addresses Contract not set"
        );
        require(
            AddressesInterface(addressesContractAddr).existingContract(
                contractAddr
            ) == true,
            "Contract does not exist"
        );
        _;
    }

    modifier verified(address contractAddr) {
        require(
            AddressesInterface(addressesContractAddr).isVerified(
                contractAddr
            ) == true,
            "Contract is not verified"
        );
        _;
    }

    function _hasOffer(
        address contractAddr,
        uint256 tokenId,
        address addr
    ) internal view returns (bool) {
        uint256 i;
        uint256 length = offers[contractAddr][tokenId].length;
        for (i = 0; i < length; ++i) {
            if (offers[contractAddr][tokenId][i].offerer == addr) {
                return true;
            }
        }
        return false;
    }

    function _hasBid(
        address contractAddr,
        uint256 tokenId,
        address addr
    ) internal view returns (bool) {
        uint256 i;
        uint256 length = bids[contractAddr][tokenId].length;
        for (i = 0; i < length; ++i) {
            if (bids[contractAddr][tokenId][i].bidder == addr) {
                return true;
            }
        }
        return false;
    }

    /// @dev Adds an sale to the list of open sales. Also fires the
    ///  SaleCreated event.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId The ID of the token to be put on sale.
    /// @param _sale Sale to add.
    function _addSale(
        address contractAddr,
        uint256 _tokenId,
        Sale memory _sale
    ) internal {
        // Require that all sales have a duration of
        // at least one minute. (Keeps our math from getting hairy!)

        tokenIdToSales[contractAddr][_tokenId] = _sale;
        saleTokenIds[contractAddr].push(_tokenId);
        saleTokenIdsBySeller[_sale.seller][contractAddr].push(_tokenId);
    }

    function _addAuction(
        address contractAddr,
        uint256 _tokenId,
        Auction memory _auction
    ) internal {
        // Require that all sales have a duration of
        // at least one minute. (Keeps our math from getting hairy!)

        tokenIdToAuctions[contractAddr][_tokenId] = _auction;
        auctionTokenIds[contractAddr].push(_tokenId);
        auctionTokenIdsBySeller[_auction.auctioneer][contractAddr].push(
            _tokenId
        );
    }

    /// @dev Cancels an sale unconditionally.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of the token price we are canceling.
    function _cancelSale(address contractAddr, uint256 _tokenId) internal {
        _transfer(
            contractAddr,
            tokenIdToSales[contractAddr][_tokenId].seller,
            _tokenId
        );
        _removeSale(contractAddr, _tokenId);
    }

    function _cancelAuction(address contractAddr, uint256 _tokenId) internal {
        _transfer(
            contractAddr,
            tokenIdToAuctions[contractAddr][_tokenId].auctioneer,
            _tokenId
        );
        _removeAuction(contractAddr, _tokenId);
    }

    function _purchase(
        address contractAddr,
        uint256 _tokenId,
        address seller,
        string memory payment,
        uint256 _buyPrice,
        uint256 price
    ) internal {
        // The bid is good! Remove the sale before sending the fees
        // to the sender so we can't have a reentrancy attack.
        uint256 saleValue;
        uint256 remaining;
        // Transfer proceeds to seller (if there are any!)
        if (_buyPrice > price) {
            remaining = _buyPrice - price;
        }
        if (price > 0) {
            // Calculate the saler's cut.
            // (NOTE: _computeCut() is guaranteed to return a
            // value <= price, so this subtraction can't go negative.)
            // uint256 salerCut = _computeCut(price);
            // uint256 sellerProceeds = price - salerCut;
            // NOTE: Doing a transfer() in the middle of a complex
            // method like this is generally discouraged because of
            // reentrancy attacks and DoS attacks if the seller is
            // a contract with an invalid fallback function. We explicitly
            // guard against reentrancy attacks by removing the sale
            // before calling transfer(), and the only thing the seller
            // can DoS is the sale of their own asset! (And if it's an
            // accident, they can call cancelSale(). )
            if (hasRoyalty(contractAddr)) {
                saleValue = _deduceRoyalties(contractAddr, _tokenId, price);
            } else {
                saleValue = price;
            }
            _transferIncludeFee(
                address(this),
                seller,
                payment,
                saleValue,
                true
            );
        }
    }

    function _transferIncludeFee(
        address sender,
        address receiver,
        string memory payment,
        uint256 price,
        bool includeFee
    ) internal {
        uint256 feeAmount = 0;
        if (includeFee == true) {
            feeAmount = (price * feePercent[payment]) / 10000;
        }
        if (
            keccak256(abi.encodePacked("BNB")) ==
            keccak256(abi.encodePacked(payment)) &&
            sender == address(this)
        ) {
            payable(receiver).transfer(price - feeAmount);
            payable(feeAddress).transfer(feeAmount);
        }
    }

    /// @dev Computes the price and transfers winnings.
    /// Does NOT transfer ownership of token.
    function _buy(
        address contractAddr,
        uint256 _tokenId,
        address _user,
        uint256 _buyPrice
    ) internal returns (uint256) {
        // Get a reference to the sale struct
        Sale storage sale = tokenIdToSales[contractAddr][_tokenId];
        // Check that the buy is greater than or equal to the current price
        uint256 price = sale.price;
        require(_buyPrice >= price, "Buy price should be bigger");

        // Grab a reference to the seller before the sale struct
        // gets deleted.
        _transferIncludeFee(
            _user,
            address(this),
            sale.payment,
            _buyPrice,
            false
        );
        _purchase(
            contractAddr,
            _tokenId,
            sale.seller,
            sale.payment,
            _buyPrice,
            price
        );
        _removeSale(contractAddr, _tokenId);

        return price;
    }

    /// @dev Removes an sale from the list of open sales.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of NFT on sale.
    function _removeSale(address contractAddr, uint256 _tokenId) internal {
        uint256 i;
        uint256 length = saleTokenIds[contractAddr].length;
        for (i = 0; i < length; ++i) {
            if (saleTokenIds[contractAddr][i] == _tokenId) {
                break;
            }
        }
        require(i < length, "No sale for this NFT");
        saleTokenIds[contractAddr][i] = saleTokenIds[contractAddr][length - 1];
        saleTokenIds[contractAddr].pop();
        Sale storage sale = tokenIdToSales[contractAddr][_tokenId];
        length = saleTokenIdsBySeller[sale.seller][contractAddr].length;
        for (
            i = 0;
            saleTokenIdsBySeller[sale.seller][contractAddr][i] != _tokenId;
            ++i
        ) {}
        saleTokenIdsBySeller[sale.seller][contractAddr][
            i
        ] = saleTokenIdsBySeller[sale.seller][contractAddr][length - 1];
        saleTokenIdsBySeller[sale.seller][contractAddr].pop();
        delete tokenIdToSales[contractAddr][_tokenId];
        length = offers[contractAddr][_tokenId].length;
        for (i = 0; i < length; ++i) {
            _transferIncludeFee(
                address(this),
                address(offers[contractAddr][_tokenId][i].offerer),
                offers[contractAddr][_tokenId][i].payment,
                offers[contractAddr][_tokenId][i].price,
                false
            );
        }
        delete offers[contractAddr][_tokenId];
    }

    function _removeAuction(address contractAddr, uint256 _tokenId) internal {
        uint256 i;
        uint256 length = auctionTokenIds[contractAddr].length;
        for (i = 0; i < length; ++i) {
            if (auctionTokenIds[contractAddr][i] == _tokenId) {
                break;
            }
        }
        require(i < length, "No auction for this NFT");
        auctionTokenIds[contractAddr][i] = auctionTokenIds[contractAddr][
            length - 1
        ];
        auctionTokenIds[contractAddr].pop();
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        length = auctionTokenIdsBySeller[auction.auctioneer][contractAddr]
            .length;
        for (
            i = 0;
            auctionTokenIdsBySeller[auction.auctioneer][contractAddr][i] !=
            _tokenId;
            ++i
        ) {}
        auctionTokenIdsBySeller[auction.auctioneer][contractAddr][
            i
        ] = auctionTokenIdsBySeller[auction.auctioneer][contractAddr][
            length - 1
        ];
        auctionTokenIdsBySeller[auction.auctioneer][contractAddr].pop();
        delete tokenIdToAuctions[contractAddr][_tokenId];
        length = bids[contractAddr][_tokenId].length;
        for (i = 0; i < length; ++i) {
            _transferIncludeFee(
                address(this),
                bids[contractAddr][_tokenId][i].bidder,
                bids[contractAddr][_tokenId][i].payment,
                bids[contractAddr][_tokenId][i].price,
                false
            );
        }
        delete bids[contractAddr][_tokenId];
    }

    /// @param contractAddr - Address of current Smart Contract
    function getSaleTokens(address contractAddr)
        public
        view
        returns (uint256[] memory)
    {
        return saleTokenIds[contractAddr];
    }

    function getAuctionTokens(address contractAddr)
        public
        view
        returns (uint256[] memory)
    {
        return auctionTokenIds[contractAddr];
    }

    function ownerOf(address contractAddr, uint256 _tokenId)
        public
        view
        returns (address)
    {
        ERC721 nftContract = ERC721(contractAddr);
        return nftContract.ownerOf(_tokenId);
    }

    /// @param contractAddr - Address of current Smart Contract
    function tokenURI(address contractAddr, uint256 tokenId)
        public
        view
        returns (string memory)
    {
        ERC721 nftContract = ERC721(contractAddr);
        return nftContract.tokenURI(tokenId);
    }

    /// @dev Escrows the NFT, assigning ownership to this contract.
    /// Throws if the escrow fails.
    /// @param _owner - Current owner address of token to escrow.
    /// @param _tokenId - ID of token whose approval to verify.
    function _escrow(
        address contractAddr,
        address _owner,
        uint256 _tokenId
    ) internal {
        // it will throw if transfer fails
        ERC721 nftContract = ERC721(contractAddr);
        nftContract.transferFrom(_owner, address(this), _tokenId);
    }

    function _transfer(
        address contractAddr,
        address _receiver,
        uint256 _tokenId
    ) internal {
        // it will throw if transfer fails
        ERC721 nftContract = ERC721(contractAddr);
        nftContract.transferFrom(address(this), _receiver, _tokenId);
    }

    function _send(
        address contractAddr,
        address _sender,
        address _receiver,
        uint256 _tokenId
    ) internal {
        ERC721 nftContract = ERC721(contractAddr);
        nftContract.transferFrom(_sender, _receiver, _tokenId);
    }

    function _createOffer(
        address contractAddr,
        uint256 tokenId,
        address offerer,
        string memory payment,
        uint256 price
    ) internal {
        offers[contractAddr][tokenId].push(Offer(address(0), "", 0, 0));
        uint256 length = offers[contractAddr][tokenId].length;
        uint256 i;
        for (
            i = length - 1;
            i > 0 && offers[contractAddr][tokenId][i - 1].price > price;
            --i
        ) {
            offers[contractAddr][tokenId][i] = offers[contractAddr][tokenId][
                i - 1
            ];
        }
        offers[contractAddr][tokenId][i] = Offer(
            offerer,
            payment,
            price,
            block.timestamp
        );
    }

    function _bid(
        address contractAddr,
        uint256 tokenId,
        address bidder,
        string memory payment,
        uint256 price
    ) internal {
        bids[contractAddr][tokenId].push(
            Bid(bidder, payment, price, block.timestamp)
        );
    }

    function acceptOffer(address contractAddr, uint256 _tokenId)
        external
        exists(contractAddr)
        onSale(contractAddr, _tokenId)
        onlySeller(contractAddr, _tokenId)
    {
        uint256 offerLength = offers[contractAddr][_tokenId].length;
        require(offerLength > 0, "There is no offer on this token");
        address buyer = offers[contractAddr][_tokenId][offerLength - 1].offerer;
        uint256 price = offers[contractAddr][_tokenId][offerLength - 1].price;
        offers[contractAddr][_tokenId].pop();
        _purchase(
            contractAddr,
            _tokenId,
            tokenIdToSales[contractAddr][_tokenId].seller,
            tokenIdToSales[contractAddr][_tokenId].payment,
            price,
            price
        );
        _transfer(contractAddr, buyer, _tokenId);
        _removeSale(contractAddr, _tokenId);
    }

    function acceptBid(address contractAddr, uint256 _tokenId)
        external
        exists(contractAddr)
        onAuction(contractAddr, _tokenId)
        onlyAuctioneer(contractAddr, _tokenId)
    {
        uint256 bidlength = bids[contractAddr][_tokenId].length;
        require(bidlength > 0, "There is no bid on this auction");
        address buyer = bids[contractAddr][_tokenId][bidlength - 1].bidder;
        uint256 price = bids[contractAddr][_tokenId][bidlength - 1].price;
        bids[contractAddr][_tokenId].pop();
        _purchase(
            contractAddr,
            _tokenId,
            tokenIdToAuctions[contractAddr][_tokenId].auctioneer,
            tokenIdToAuctions[contractAddr][_tokenId].payment,
            price,
            price
        );
        _removeAuction(contractAddr, _tokenId);
        _transfer(contractAddr, buyer, _tokenId);
    }

    /// @notice Checks if NFT contract implements the ERC-2981 interface
    /// @param _contract - the address of the NFT contract to query
    /// @return true if ERC-2981 interface is supported, false otherwise
    function hasRoyalty(address _contract) public view returns (bool) {
        bool success = IERC2981(_contract).supportsInterface(0x2a55205a); //_INTERFACE_ID_ERC2981=0x2a55205a
        return success;
    }

    function getRoyalty(address contractAddr, uint256 tokenId)
        external
        view
        exists(contractAddr)
        returns (address, uint256)
    {
        require(
            hasRoyalty(contractAddr) == true,
            "Contract does not have royalty"
        );
        (address recipient, uint256 royalty) = IERC2981(contractAddr)
            .royaltyInfo(tokenId, 10000);
        return (recipient, royalty);
    }

    /// @notice Transfers royalties to the rightsowner if applicable
    /// @param tokenId - the NFT assed queried for royalties
    /// @param grossSaleValue - the price at which the asset will be sold
    /// @return netSaleAmount - the value that will go to the seller after
    ///         deducting royalties
    function _deduceRoyalties(
        address contractAddr,
        uint256 tokenId,
        uint256 grossSaleValue
    ) internal returns (uint256 netSaleAmount) {
        // Get amount of royalties to pays and recipient
        (address royaltiesReceiver, uint256 royaltiesAmount) = IERC2981(
            contractAddr
        ).royaltyInfo(tokenId, grossSaleValue);
        // Deduce royalties from sale value
        uint256 netSaleValue = grossSaleValue - royaltiesAmount;
        // Transfer royalties to rightholder if not zero
        if (royaltiesAmount > 0) {
            payable(royaltiesReceiver).transfer(royaltiesAmount);
        }
        return netSaleValue;
    }
}
