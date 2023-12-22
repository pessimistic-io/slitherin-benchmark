// SPDX-License-Identifier: MIT

//   ##         ######     #######   ######     #######
//   ##         ##    ##   ##        ##    ##   ##
//   ##         ##    ##   ##        ##    ##   ##
//   ##         ## ####    ######    ## ####    ######
//   ##         ##         ##        ##         ##
//   ##         ##         ##        ##         ##
//   ########   ##         #######   ##         #######
//   Webside: https://ladypepe.xyz
//   twitter: LadyPepeFinance
//   discord: https://discord.com/channels/krvQ6JTpSh

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeMath.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract LPEPEDROP is Ownable, Pausable {
    using SafeMath for uint256;

    address public admin;
    IERC20 public token;
    IERC721 public nftContract;
    uint256 public tokenAmount;
    uint256 public claimedCount;
    mapping(uint256 => bool) public claimedIds;
    mapping(address => uint256) public claimedAmounts;
    mapping(address => bool) public isRecipientClaimed;
    address[] public claimedRecipients;

    event TokensClaimed(address indexed recipient, uint256 amount);
    event DistributionEndTimeUpdated(uint256 newEndTime);

    constructor(IERC20 _token, IERC721 _nftContract, uint256 _tokenAmount) {
        admin = msg.sender;
        token = _token;
        nftContract = _nftContract;
        tokenAmount = _tokenAmount;
    }

    function claimTokens(uint256 _tokenId) public whenNotPaused {
        require(claimedIds[_tokenId] == false, "NFT has already been claimed");
        require(nftContract.ownerOf(_tokenId) == msg.sender, "You must own the NFT to claim tokens");

        claimedIds[_tokenId] = true;
        claimedCount += 1;

        claimedAmounts[msg.sender] = claimedAmounts[msg.sender].add(tokenAmount);
        uint256 contractBalance = token.balanceOf(address(this));
        require(claimedAmounts[msg.sender] <= contractBalance, "Insufficient token balance in contract");

        if (!isRecipientClaimed[msg.sender]) {
            claimedRecipients.push(msg.sender);
            isRecipientClaimed[msg.sender] = true;
        }

        bool success = token.transfer(msg.sender, tokenAmount);
        require(success, "Token transfer failed");

        emit TokensClaimed(msg.sender, tokenAmount);
    }

    function getClaimedAmount(address _recipient) public view returns (uint256) {
        return claimedAmounts[_recipient];
    }

    function getTokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function pauseDistribution() public onlyOwner {
        _pause();
    }

    function unpauseDistribution() public onlyOwner {
        _unpause();
    }

    function withdraw(uint256 amount) public onlyOwner {
        require(amount <= token.balanceOf(address(this)), "Insufficient token balance in contract");
        token.transfer(admin, amount);
    }
}
