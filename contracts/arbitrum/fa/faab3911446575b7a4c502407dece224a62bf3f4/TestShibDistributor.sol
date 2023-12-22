//SPDX-License-Identifier: MIT
pragma solidity >= 0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC721Enumerable.sol";

contract TestShibDistributor is Ownable {
    IERC20 public immutable testShibToken;
    IERC721Enumerable public immutable testShibNFT;

    mapping(address => bool) public hasClaimedTokens;

    mapping(uint256 => address) public nftIdClaimed;
    mapping(address => uint256[]) public nftOwned;


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
        IERC721Enumerable _nftAddress
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


    function getNFTTokenIDs(address _walletAddress) public view returns (uint256[] memory) {
        uint256 nftBalance = testShibNFT.balanceOf(_walletAddress);
        uint256[] memory tokenIDs = new uint256[](nftBalance);
        for (uint256 i = 0; i < nftBalance; i++) {
            tokenIDs[i] = testShibNFT.tokenOfOwnerByIndex(_walletAddress, i);
        }
        return tokenIDs;
    }

    function addNFT() public{
        uint256[] memory mynfts = getNFTTokenIDs(msg.sender);
        for(uint256 i = 0; i < mynfts.length; i++) {
            nftOwned[msg.sender].push(mynfts[i]);
        }
    }

    function claimTokensForNFT() public claimIsLive {
        uint256 validTokenCount = 0;
        uint256[] memory ownedTokens = nftOwned[msg.sender];
        for(uint256 i = 0; i < ownedTokens.length; i++) {
            uint256 _tokenId = ownedTokens[i];
            require(nftIdClaimed[_tokenId] == address(0), "Tokens already claimed");
            validTokenCount += 1;
            nftIdClaimed[_tokenId] = msg.sender;
        }
        require(validTokenCount > 0, "No tokens to claim");

        uint256 amountOfTokensToClaim;
        if(validTokenCount<= 2) {
            amountOfTokensToClaim = (25 * claimPerNFT) / 100;
        } else if(validTokenCount > 2 && validTokenCount <= 4){
            amountOfTokensToClaim = (125 * claimPerNFT) / 100;
        } else if(validTokenCount > 4 && validTokenCount <= 9) {
            amountOfTokensToClaim = (250 * claimPerNFT) / 100;
        } else if(validTokenCount > 10) {
            amountOfTokensToClaim = (300 * claimPerNFT) / 100;
        }

        totalTokensClaimed += amountOfTokensToClaim;
        require(testShibToken.transfer(msg.sender, amountOfTokensToClaim), "Transfer failed");
        emit HasClaimedTokens(msg.sender, amountOfTokensToClaim); 
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
