// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomNFT is ERC721Enumerable, Ownable {
    uint256 public totalMinted;
    mapping(uint256 => string) private tokenUris;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        totalMinted = 0;
    }

    function mint(string memory uri, uint256 cnt) external {
        uint256 i;
        for (i = 0; i < cnt; ++i) {
            _safeMint(msg.sender, ++totalMinted);
            tokenUris[totalMinted] = uri;
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return tokenUris[tokenId];
    }

    function batchApprove(address _to, uint256[] memory _tokenIds) external {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            approve(_to, _tokenIds[i]);
        }
    }
}
