// SPDX-License-Identifier: MIT
/*          

//      _   ___ _____ ___    _   _    _____  __   ___ _    ___  _   _ ___  
//     /_\ / __|_   _| _ \  /_\ | |  |_ _\ \/ /  / __| |  / _ \| | | |   \ 
//    / _ \\__ \ | | |   / / _ \| |__ | | >  <  | (__| |_| (_) | |_| | |) |
//   /_/ \_\___/ |_| |_|_\/_/ \_\____|___/_/\_\  \___|____\___/ \___/|___/ 
// 
//   D·M                                                                                                                                                                                      
*/

pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";
import "./IERC20.sol";

contract ClaimAstralix {
    address public owner;
    IERC721Enumerable public astralixERC721;
    IERC20 public token;

    uint public claimRate;
    uint private totalTokensClaimed; // Total amount of tokens claimed
    mapping(uint => bool) private blockedTokens; // Mapping to track blocked tokens
    mapping(uint => uint) private tokensClaimedByTokenId;
    mapping(address => uint) private tokensClaimedByAddress;

    constructor(address _nft, address _token, uint _claimRate) {
        owner = msg.sender;
        astralixERC721 = IERC721Enumerable(_nft);
        token = IERC20(_token);
        claimRate = _claimRate;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    function setClaimRate(uint _claimRate) public onlyOwner {
        claimRate = _claimRate;
    }

    function claimTokens() public {
        uint nftCount = astralixERC721.balanceOf(msg.sender);
        require(nftCount > 0, "You do not have NFTs to claim token");

        uint totalClaimAmount = 0;
        for (uint i = 0; i < nftCount; i++) {
            uint tokenId = astralixERC721.tokenOfOwnerByIndex(msg.sender, i);
            if (!blockedTokens[tokenId]) {
                blockedTokens[tokenId] = true;
                totalClaimAmount += claimRate;
                tokensClaimedByTokenId[tokenId] += claimRate;
            }
        }
        require(totalClaimAmount > 0, "All previously claimed NFTs");
        totalTokensClaimed += totalClaimAmount; // Update total tokens claimed
        tokensClaimedByAddress[msg.sender] += totalClaimAmount;
        bool success = token.transfer(msg.sender, totalClaimAmount);
        require(success, "The transfer has failed.");
    }

    function withdrawTokens() public onlyOwner {
        uint contractBalance = token.balanceOf(address(this));
        require(contractBalance > 0, "There are no tokens to withdraw.");

        bool success = token.transfer(owner, contractBalance);
        require(success, "The transfer has failed.");
    }

    function isTokenBlocked(uint tokenId) public view returns (bool) {
        return blockedTokens[tokenId];
    }

    function blockOrUnblockTokens(
        uint[] memory tokenIds,
        bool blockStatus
    ) public onlyOwner {
        for (uint i = 0; i < tokenIds.length; i++) {
            blockedTokens[tokenIds[i]] = blockStatus;
        }
    }

    function getTotalTokensClaimed() public view returns (uint) {
        return totalTokensClaimed;
    }

    function getTokensClaimedByTokenId(
        uint tokenId
    ) public view returns (uint) {
        require(tokenId < astralixERC721.totalSupply(), "Invalid TokenId");
        return tokensClaimedByTokenId[tokenId];
    }

    function getTokensClaimedByAddress(
        address wallet
    ) public view returns (uint) {
        return tokensClaimedByAddress[wallet];
    }

    function getTokensClaimableByAddress(
        address wallet
    ) public view returns (uint) {
        uint nftCount = astralixERC721.balanceOf(wallet);
        uint claimableTokens = 0;

        for (uint i = 0; i < nftCount; i++) {
            uint tokenId = astralixERC721.tokenOfOwnerByIndex(wallet, i);
            if (!blockedTokens[tokenId]) {
                claimableTokens += claimRate;
            }
        }

        return claimableTokens;
    }
}

