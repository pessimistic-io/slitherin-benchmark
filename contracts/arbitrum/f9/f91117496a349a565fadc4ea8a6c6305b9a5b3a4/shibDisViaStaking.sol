//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IERC721.sol";
import "./IERC20.sol";
import "./IERC721Receiver.sol";
import "./MerkleProof.sol";
import "./Address.sol";
import "./Ownable.sol";

contract DistributorViaStaking is Ownable, IERC721Receiver {

    using Address for address;

    bytes32 public merkleRootOG;
    bytes32 public merkleRootARB;
    
    mapping(address => mapping(uint256 => uint256)) public deposits;
    mapping(address => bool) public isStaking;
    mapping(address => uint256[]) public stakedNfts;
    mapping(address => bool) public hasClaimedTokens;

    uint256 stakingDuration = 7 days;

    uint256 public totalTokensClaimed;
    uint256 public ARBclaimCount;
    uint256 public maxAddressForARBclaim = 150000;
    uint256 public claimPerOG = 300000000000 * 10 ** 6;
    uint256 public claimPerArbWallet = 420000000000 * 10 ** 6;
    uint256 public claimPerNFT = 5900000000000 * 10 ** 6;

    IERC721 public immutable nftContract;
    IERC20 public immutable tokenContract;

    bool public _claimIsLive = false;

    event HasClaimedTokens(address indexed recipient, uint256 amount);
    event HasStakedNFT(address indexed sender, uint256 amount, uint256 timestamp);
    event HasUnstakedNFT(address indexed sender, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);


    constructor(address _tokenContract, address _nftContract) {
        tokenContract = IERC20(_tokenContract);
        nftContract = IERC721(_nftContract);
    }

    modifier claimIsLive() {
        require(_claimIsLive == true, "Claim is not live");
        _;
    }

    function _checkTokenIds(address _user) public view returns (uint256[] memory) {
        uint256 amount = nftContract.balanceOf(_user);
        uint256[] memory tokenIds = new uint256[](amount);
        uint256 index = 0;
        for(uint256 i = 1; i < 48001; i++) {
            require(index < amount, "Retrieved all tokenIds");
            if(_user == nftContract.ownerOf(i)) {
                tokenIds[index] = i;
                index += 1;
            }
        } 
        return tokenIds;
    }

    function depositNFT(uint256[] memory _tokenIds) public {
        uint256 depositTimestamp = block.timestamp;
        uint256 noOfNfts = _tokenIds.length;
        require(noOfNfts > 0, "balance of nfts must be greater than zero");

        for(uint256 i = 0; i < noOfNfts; i++) {
            uint256 tokenId = _tokenIds[i];
            require(nftContract.ownerOf(tokenId) == msg.sender, "You must own the nft");
            require(deposits[msg.sender][tokenId] == 0, "You have already deposited");

            nftContract.safeTransferFrom(msg.sender, address(this), tokenId);
            deposits[msg.sender][tokenId] = depositTimestamp;
        }

        isStaking[msg.sender] = true;
        emit HasStakedNFT(msg.sender, noOfNfts, depositTimestamp);
    }

    function withdrawNFT(uint256[] memory _tokenIds) public {
        uint256 noOfNfts = _tokenIds.length;
        require(noOfNfts > 0, "balance of nfts must be greater than zero");

        for(uint256 i = 0; i < noOfNfts; i++) {
            uint256 tokenId = _tokenIds[i];
            require(deposits[msg.sender][tokenId] != 0, "You have no deposit");
            require(block.timestamp > (deposits[msg.sender][tokenId] + stakingDuration), "Staking duration not due");
            
            delete deposits[msg.sender][tokenId];
            nftContract.safeTransferFrom(address(this), msg.sender, tokenId);
        }

        isStaking[msg.sender] = false;
        emit HasUnstakedNFT(msg.sender, noOfNfts);
    }

    function claimTokenForNFT(uint256[] memory _tokenIds) public claimIsLive {
        require(isStaking[msg.sender] == true, "You must stake your nft(s) before claiming");
        uint256 noOfNfts = _tokenIds.length;
        require(noOfNfts > 0, "balance of nfts must be greater than zero");

        uint256 amountOfTokensToClaim;
        if(noOfNfts<= 2) {
            amountOfTokensToClaim = (25 * claimPerNFT) / 100;
        } else if( noOfNfts > 2 && noOfNfts <= 4){
            amountOfTokensToClaim = (125 * claimPerNFT) / 100;
        } else if(noOfNfts > 4 && noOfNfts <= 9) {
            amountOfTokensToClaim = (250 * claimPerNFT) / 100;
        } else if(noOfNfts > 10) {
            amountOfTokensToClaim = (300 * claimPerNFT) / 100;
        }

        totalTokensClaimed += amountOfTokensToClaim;
        require(tokenContract.transfer(msg.sender, amountOfTokensToClaim), "Transfer failed");
        emit HasClaimedTokens(msg.sender, amountOfTokensToClaim);
    }

    function claimTokensForARB(bytes32[] calldata proof) public claimIsLive {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, merkleRootARB, leaf), "Wallet not eligible to claim");

        require(ARBclaimCount <= maxAddressForARBclaim, "sorry, claim has ended");
        require(!hasClaimedTokens[msg.sender], "You have claimed your tokens");

        hasClaimedTokens[msg.sender] = true;
        ARBclaimCount += 1;
        totalTokensClaimed += claimPerArbWallet;

        require(tokenContract.transfer(msg.sender, claimPerArbWallet), "Transfer failed");
        emit HasClaimedTokens(msg.sender, claimPerArbWallet); 
    }

    function claimTokensForOG(bytes32[] calldata proof) public claimIsLive {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, merkleRootOG, leaf), "Wallet not eligible to claim");

        require(!hasClaimedTokens[msg.sender], "You have claimed your tokens");

        totalTokensClaimed += claimPerOG;
        hasClaimedTokens[msg.sender] = true;

        require(tokenContract.transfer(msg.sender, claimPerOG), "Transfer failed");
        emit HasClaimedTokens(msg.sender, claimPerOG); 
    }

    function setStakingDuration(uint256 _days) external onlyOwner {
        stakingDuration = _days;
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

    function setMerkleRootARB(bytes32 _merkleRoot) external onlyOwner {
        merkleRootARB = _merkleRoot;
    }

     function setMerkleRootOG(bytes32 _merkleRoot) external onlyOwner {
        merkleRootOG = _merkleRoot;
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(tokenContract.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawal(msg.sender, amount);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
