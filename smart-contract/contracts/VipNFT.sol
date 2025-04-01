// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title VipNFT Smart Contract
 * @notice Here is the logic for introducing NFT statuses to users.
 * @dev This contract allows users to mint VIP NFTs and retrieve their VIP levels.
 */
contract VipNFT is ERC721Enumerable, Ownable {
    enum VipLevel {NONE, SILVER, GOLD, PLATINUM}

    mapping (uint256 => VipLevel) public vipLevels;
    mapping (address => bool) public hasVip;

    constructor() ERC721("VIP STATUS", "VIP") Ownable(msg.sender) {}

    /**
     * @notice Allows you to mint NFT status
     * @param to the address of the status NFT
     * @param level the VIP level
     */
     function mintVIP(address to, VipLevel level) external onlyOwner {
        require(!hasVip[to], "User already has VIP status");
        uint256 tokenId = totalSupply() + 1;
        _safeMint(to, tokenId);
        vipLevels[tokenId] = level;
        hasVip[to] = true;
    }

    /**
     * @notice Retrieves the VIP level of a user
     * @param player the address of the player
     */
    function getVipLevel(address player) external view returns (VipLevel) {
        uint256 balance = balanceOf(player);
        if (balance == 0) return VipLevel.NONE;
        uint256 tokenId = tokenOfOwnerByIndex(player, 0);
        return vipLevels[tokenId];
    }
}