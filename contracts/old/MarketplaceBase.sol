// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import "../libraries/ArrayLibrary.sol";
import "../libraries/RoyaltyLibrary.sol";

import "../interfaces/AddressesInterface.sol";

abstract contract MarketplaceBase is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    address public addressesContractAddr;
    address public sparkTokenContractAddr;
    mapping(address => uint256[2]) private claimable;
    mapping(address => uint256[]) internal saleTokenIds;
    mapping(address => mapping(address => uint256[]))
        internal saleTokenIdsBySeller;
    mapping(address => uint256[]) internal auctionTokenIds;
    mapping(address => mapping(address => uint256[]))
        internal auctionTokenIdsBySeller;

    bytes4 private constant INTERFACE_SIGNATURE_ERC2981 = 0x2a55205a;

    event RoyaltiesPaid(address contractAddr, uint256 tokenId, uint256 royalty);

    modifier isProperContract(address contractAddr) {
        require(
            addressesContractAddr != address(0),
            "Addresses Contract not set"
        );
        require(
            AddressesInterface(addressesContractAddr).isVerified(contractAddr),
            "The Contract is not verified"
        );
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function _escrowFund(uint8 payment, uint256 price) internal {
        if (payment == 1) {
            require(msg.value >= price, "Insufficient Fund");
        } else {
            IERC20(sparkTokenContractAddr).transferFrom(
                msg.sender,
                address(this),
                price
            );
        }
    }

    function _transferFund(
        uint8 payment,
        uint256 price,
        address destination
    ) internal {
        if (payment == 1) {
            payable(destination).transfer(price);
        } else {
            IERC20(sparkTokenContractAddr).transfer(destination, price);
        }
    }

    function _payFund(
        uint8 payment,
        uint256 price,
        address destination,
        address contractAddr,
        uint256 tokenId
    ) internal {
        uint256 saleValue;
        if (RoyaltyLibrary.hasRoyalty(contractAddr)) {
            saleValue = RoyaltyLibrary.deduceRoyalties(
                contractAddr,
                tokenId,
                payment == 1 ? address(0) : sparkTokenContractAddr,
                price
            );
        } else {
            saleValue = price;
        }
        _transferFund(payment, saleValue, destination);
    }

    function _addClaimable(
        address to,
        uint8 payment,
        uint256 amount
    ) internal {
        claimable[to][payment - 1] += amount;
    }

    function setAddressesContractAddr(address contractAddr) external onlyOwner {
        addressesContractAddr = contractAddr;
    }

    function setSparkTokenContractAddr(address newSparkAddr)
        external
        onlyOwner
    {
        sparkTokenContractAddr = newSparkAddr;
    }

    function getSaleTokens(address contractAddr)
        public
        view
        isProperContract(contractAddr)
        returns (uint256[] memory)
    {
        return saleTokenIds[contractAddr];
    }

    function getSaleTokensBySeller(address contractAddr, address seller)
        public
        view
        isProperContract(contractAddr)
        returns (uint256[] memory)
    {
        return saleTokenIdsBySeller[seller][contractAddr];
    }

    function getClaimable(address user, uint256 index)
        external
        view
        returns (uint256)
    {
        return claimable[user][index - 1];
    }

    function claim(uint256 amount, uint8 index) external {
        require(
            amount <= claimable[msg.sender][index - 1],
            "Exceeds claimable amount"
        );
        claimable[msg.sender][index - 1] -= amount;
        _transferFund(index, amount, msg.sender);
    }
}
