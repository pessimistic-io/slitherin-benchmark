//SPDX-License-Identifier: MIT
pragma solidity >= 0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC721A.sol";

contract shibDis2 is Ownable {
    IERC20 public immutable testShibToken;
    IERC721A public immutable testShibNFT;

    mapping(address => uint256) public nftBalances;
    mapping(address => bool) public hasClaimedTokens;
    mapping(address => bool) public hasClaimedNFT;

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
        IERC721A _nftAddress
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

    function takeSnapshot() external onlyOwner {
        uint256 totalSupply = testShibNFT.totalSupply();
        
        for (uint256 i = 1; i < (totalSupply + 1); i++) {
            address owner = testShibNFT.ownerOf(i);
            nftBalances[owner]++;
        }
    }

    function claimTokensForNft() public claimIsLive {
        uint256 _amount = nftBalances[msg.sender];
        require(_amount > 0, "You do not own any NFT");
        require(!hasClaimedNFT[msg.sender], "You have claimed your Tokens");

        uint256 amountOfTokensToClaim;
        if(_amount<= 2) {
            amountOfTokensToClaim = (25 * claimPerNFT) / 100;
        } else if( _amount > 2 && _amount <= 4){
            amountOfTokensToClaim = (125 * claimPerNFT) / 100;
        } else if(_amount > 4 && _amount <= 9) {
            amountOfTokensToClaim = (250 * claimPerNFT) / 100;
        } else if(_amount > 10) {
            amountOfTokensToClaim = (300 * claimPerNFT) / 100;
        }

        totalTokensClaimed += amountOfTokensToClaim;
        hasClaimedNFT[msg.sender] = true;
        
        require(testShibToken.transfer(msg.sender, amountOfTokensToClaim), "Transfer failed");
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
