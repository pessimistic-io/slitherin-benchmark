//SPDX-License-Identifier: MIT
pragma solidity >= 0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./MerkleProof.sol";

contract ShibaiDistributorPool is Ownable {
    IERC20 public immutable tokenContract;
    IERC721 public immutable nftContract;

    bytes32 public merkleRootNFT;
    bytes32 public merkleRootARB;
    bytes32 public merkleRootOG;


    mapping(address => uint256) public nftBalances;
    mapping(address => bool) public hasClaimedTokensOG;
    mapping(address => bool) public hasClaimedTokensARB;
    mapping(address => bool) public hasClaimedNFT;
    mapping(address => bool) public userCanClaimTokens;

    uint256 public totalTokensClaimed;
    uint256 public ARBclaimCount;
    uint256 public maxAddressForARBclaim = 150000;
    uint256 public claimPerOG = 300000000000 * 10 ** 6;
    uint256 public claimPerArbWallet = 220000000000 * 10 ** 6;

    uint256 private tier1Claim = 1475000000000 * 10 ** 6;
    uint256 private tier2Claim = 3375000000000 * 10 ** 6;
    uint256 private tier3Claim = 7750000000000 * 10 ** 6;
    uint256 private tier4Claim = 17700000000000 * 10 ** 6;

    bool public _claimIsLive = false;

    event HasClaimedTokensForOG(address indexed recipient, uint256 amount);
    event HasClaimedTokensForARB(address indexed recipient, uint256 amount);
    event HasClaimedNFT(address indexed recipient, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);

    constructor(
        address _tokenAddress,
        address _nftAddress
    ) {
        require(address(_tokenAddress) != address(0), "Zero token address");
        require(address(_nftAddress) != address(0), "Zero nft address");
        _transferOwnership(msg.sender);

        tokenContract = IERC20(_tokenAddress);
        nftContract = IERC721(_nftAddress);
    }

    modifier claimIsLive() {
        require(_claimIsLive == true, "Claim is not live");
        _;
    }

    function claimTokensForNft(bytes32[] calldata proof, uint256 _amount) public claimIsLive {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, merkleRootNFT, leaf), "Wallet not eligible to claim");

        require(_amount > 0, "You do not own any tokens");
        require(!hasClaimedNFT[msg.sender], "You have claimed your Tokens");

        uint256 amountOfTokensToClaim;
        if(_amount<= 2) {
            amountOfTokensToClaim = tier1Claim;
        } else if( _amount > 2 && _amount <= 4){
            amountOfTokensToClaim = tier2Claim;
        } else if(_amount > 4 && _amount <= 9) {
            amountOfTokensToClaim = tier3Claim;
        } else if(_amount > 10) {
            amountOfTokensToClaim = tier4Claim;
        }

        totalTokensClaimed += amountOfTokensToClaim;
        hasClaimedNFT[msg.sender] = true;

        require(tokenContract.transfer(msg.sender, amountOfTokensToClaim), "Transfer failed");
        emit HasClaimedNFT(msg.sender, amountOfTokensToClaim);
    }

    function claimTokensForARB(bytes32[] calldata proof) public claimIsLive {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, merkleRootARB, leaf), "Wallet not eligible to claim");

        require(ARBclaimCount <= maxAddressForARBclaim, "sorry, claim has ended");
        require(!hasClaimedTokensARB[msg.sender], "You have claimed your tokens");

        hasClaimedTokensARB[msg.sender] = true;
        ARBclaimCount += 1;
        totalTokensClaimed += claimPerArbWallet;

        require(tokenContract.transfer(msg.sender, claimPerArbWallet), "Transfer failed");
        emit HasClaimedTokensForARB(msg.sender, claimPerArbWallet); 
    }

    function claimTokensForOG(bytes32[] calldata proof) public claimIsLive {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, merkleRootOG, leaf), "Wallet not eligible to claim");

        require(!hasClaimedTokensOG[msg.sender], "You have claimed your tokens");

        totalTokensClaimed += claimPerOG;
        hasClaimedTokensOG[msg.sender] = true;

        require(tokenContract.transfer(msg.sender, claimPerOG), "Transfer failed");
        emit HasClaimedTokensForOG(msg.sender, claimPerOG); 
    }

    function setTokenPerArbClaim(uint256 _noOfTokens) external onlyOwner {
        claimPerArbWallet = _noOfTokens * 10 ** 6;
    }

    function setTokenPerOGClaim(uint256 _noOfTokens) external onlyOwner {
        claimPerOG = _noOfTokens * 10 ** 6;
    }

    function setMerkleRootNFT(bytes32 _merkleRoot) external onlyOwner {
        merkleRootNFT = _merkleRoot;
    }

    function setMerkleRootARB(bytes32 _merkleRoot) external onlyOwner {
        merkleRootARB = _merkleRoot;
    }

    function setMerkleRootOG(bytes32 _merkleRoot) external onlyOwner {
        merkleRootOG = _merkleRoot;
    }

    function toggleClaim() external onlyOwner {
        _claimIsLive = !_claimIsLive;
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(tokenContract.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawal(msg.sender, amount);
    }
}
