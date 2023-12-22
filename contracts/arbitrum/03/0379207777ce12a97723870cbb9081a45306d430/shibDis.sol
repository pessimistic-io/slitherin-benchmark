//SPDX-License-Identifier: MIT
pragma solidity >= 0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC721.sol";

contract shibaiDis is Ownable {
    IERC20 public immutable testShibToken;
    IERC721 public immutable testShibNFT;

    mapping(address => bool) public hasClaimedTokens;
    mapping(address => bool) public hasClaimedNFT;
    mapping(address => bool) public userCanClaimTokens;

    uint256 public totalTokensClaimed;
    uint256 public ARBclaimCount;
    uint256 public maxAddressForARBclaim = 150000;
    uint256 public claimPerOG = 300000000000 * 10 ** 6;
    uint256 public claimPerArbWallet = 420000000000 * 10 ** 6;
    uint256 public claimPerNFT = 5900000000000 * 10 ** 6;

    bool public _claimIsLive = false;

    event HasClaimedTokens(address indexed recipient, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);

    constructor(
        IERC20 _tokenAddress,
        IERC721 _nftAddress
    ) {
        require(address(_tokenAddress) != address(0), "Zero token address");
        require(address(_nftAddress) != address(0), "Zero nft address");
        _transferOwnership(msg.sender);

        testShibToken = _tokenAddress;
        testShibNFT = _nftAddress;
    }

    modifier claimIsLive() {
        require(_claimIsLive == true, "Claim is not live");
        _;
    }

    function getNftOwned(address _user) public onlyOwner returns(uint256) {
        uint256 amount = testShibNFT.balanceOf(_user);
        require(amount > 0, "user owns no NFT");
        userCanClaimTokens[_user] = true;
        return amount;
    }

    function claimTokensForNft(uint256 _noOfTokens) public claimIsLive {
        require(!hasClaimedNFT[msg.sender], "You have claimed your Tokens");
        require(userCanClaimTokens[msg.sender], "You are not eligible to claim tokens");

        totalTokensClaimed += _noOfTokens;
        hasClaimedNFT[msg.sender] = true;
        require(testShibToken.transfer(msg.sender, _noOfTokens), "Transfer failed");
        emit HasClaimedTokens(msg.sender, claimPerArbWallet);
    }

    function claimTokensForARB() public claimIsLive {
        require(ARBclaimCount <= maxAddressForARBclaim, "sorry, claim has ended");
        require(!hasClaimedTokens[msg.sender], "You have claimed your tokens");

        hasClaimedTokens[msg.sender] = true;
        ARBclaimCount += 1;
        totalTokensClaimed += claimPerArbWallet;

        require(testShibToken.transfer(msg.sender, claimPerArbWallet), "Transfer failed");
        emit HasClaimedTokens(msg.sender, claimPerArbWallet); 
    }

    function claimTokensForOG() public claimIsLive {
        require(!hasClaimedTokens[msg.sender], "You have claimed your tokens");

        totalTokensClaimed += claimPerOG;
        hasClaimedTokens[msg.sender] = true;

        require(testShibToken.transfer(msg.sender, claimPerOG), "Transfer failed");
        emit HasClaimedTokens(msg.sender, claimPerOG); 
    }

    function setTokenPerArbClaim(uint256 _noOfTokens) external onlyOwner {
        claimPerArbWallet = _noOfTokens * 10 ** 6;
    }

    function setTokenPerOGClaim(uint256 _noOfTokens) external onlyOwner {
        claimPerOG = _noOfTokens * 10 ** 6;
    }

    function setTokenForNftClaim(uint256 _noOfTokens) external onlyOwner {
        claimPerNFT = _noOfTokens * 10 ** 6;
    }

    function toggleClaim() external onlyOwner {
        _claimIsLive = !_claimIsLive;
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(testShibToken.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawal(msg.sender, amount);
    }
}
