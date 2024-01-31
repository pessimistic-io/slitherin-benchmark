// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC721Holder.sol";
import "./IERC721.sol";

interface INFT {
    function walletOfOwner(address _owner) external view returns (uint256[] memory);
}

contract COSMIC is ERC20, ERC721Holder, Ownable {


    address public nft;
    address public martianNft;

    ERC20 private oldToken;

    mapping(uint256 => address) public tokenOwnerOf; // owner of token id
    mapping(uint256 => uint256) public tokenStakedAt; // staked at what timestamp

    mapping(uint256 => address) public tokenOwnerOfMartian; // owner of token id
    mapping(uint256 => uint256) public tokenStakedAtMartian; // staked at what timestamp

    uint256 public EMISSION_RATE = (1 * 10 ** decimals()) / 1 days;
    uint256 public MARTIAN_EMISSION_RATE = (1 * 10 ** decimals()) / 1 days;

    // Constructor
    constructor(address _oldToken, address _nft, address _martianNft) ERC20("COSMIC v2", "COSMIC"){
        oldToken = ERC20(_oldToken);
        nft = _nft;
        martianNft = _martianNft;
        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    // Fuction to Set NFT Contract
    function updateNftContract(address _nft, address _martianNft) public onlyOwner {
        nft = _nft;
        martianNft = _martianNft;
    }

    // Additional token minting by owner
    function additionalMinting(uint256 _amount) public onlyOwner {
        _mint(msg.sender, _amount);
    }

    // Change emission rate for martian nft
    function changeRewardsMartian(uint256 _rate) external onlyOwner {
        MARTIAN_EMISSION_RATE = (_rate * 10 ** decimals()) / 1 days;
    }

    // Change emission rate for GEX NFT
    function changeRewards(uint256 _rate) external onlyOwner {
        EMISSION_RATE = (_rate * 10 ** decimals()) / 1 days;
    }

    // Stake Function
    function stake(uint256 tokenId) external {
        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);
        tokenOwnerOf[tokenId] = msg.sender;
        tokenStakedAt[tokenId] = block.timestamp;
    }

    // Calculate Staked Tokens for a Specific NFT
    function calculateTokens(uint256 tokenId) public view returns (uint256) {
        require(tokenStakedAt[tokenId] > 0, "Token Not Staked");
        uint256 timeElapsed = block.timestamp - tokenStakedAt[tokenId];
        return timeElapsed * EMISSION_RATE;
    }

    // Unstake Function
    function unstake(uint256 tokenId) external {
        require(tokenOwnerOf[tokenId] == msg.sender, "You can't unstake");
        _mint(msg.sender, calculateTokens(tokenId)); // Minting the tokens for staking
        IERC721(nft).transferFrom(address(this), msg.sender, tokenId);
        delete tokenOwnerOf[tokenId];
        delete tokenStakedAt[tokenId];
    }

    // Batch Staking of NFTs Function
    function batchStake(uint256[] memory tokenId) external returns (bool status){
        uint256 len = tokenId.length;
        for(uint256 i=0 ; i<len; i++){
            IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId[i]);
            tokenOwnerOf[tokenId[i]] = msg.sender;
            tokenStakedAt[tokenId[i]] = block.timestamp;
        }
        return true;
    }

    // Batch Unstaking of NFTs Function
    function batchUnstake(uint256[] memory tokenId) external checkStake(tokenId) returns (bool status){
        _mint(msg.sender, batchCalculateTokens(tokenId)); // Minting the tokens for staking
        for(uint256 i=0 ; i<tokenId.length; i++){
            IERC721(nft).transferFrom(address(this), msg.sender, tokenId[i]);
            delete tokenOwnerOf[tokenId[i]];
            delete tokenStakedAt[tokenId[i]];
        }
        return true;
    }

    // Calculate total tokens of all NFTs to unstake function
    function batchCalculateTokens(uint256[] memory tokenId) public view returns (uint256) {
        uint256 totalToken;
        for(uint256 i=0 ; i<tokenId.length; i++){
            if(tokenStakedAt[tokenId[i]] > 0){
                uint256 timeElapsed = block.timestamp - tokenStakedAt[tokenId[i]];
                totalToken += timeElapsed * EMISSION_RATE;
            }  
        }        
        return totalToken;
    }

    // Exchange old token with new token function
    function exchangeToken() external {
        uint256 amount = oldToken.balanceOf(msg.sender);
        require(amount > 0, "Insufficient balance to withdraw");
        _mint(msg.sender, amount);
        oldToken.transferFrom(msg.sender,0x000000000000000000000000000000000000dEaD, amount);
    }

    //show yield of a user function
    function showYield(address user) public view returns(uint256) {
        uint[] memory tokenIds = getTokensOwnedByUser(user);
        if (tokenIds.length > 0){
            return batchCalculateTokens(tokenIds);
        }
        return 0;        
    }

    // withdraw yield without unstaking nft function
    function withdrawYield(address user) external returns(uint256) {
        require(user == msg.sender, "You can't withdraw tokens");
        uint[] memory tokenIds = getTokensOwnedByUser(user);
        uint256 totalToken;
        for(uint256 i=0; i<tokenIds.length ; i++){
            if(tokenStakedAt[tokenIds[i]] > 0){
                uint256 timeElapsed = block.timestamp - tokenStakedAt[tokenIds[i]];
                totalToken += timeElapsed * EMISSION_RATE;
                tokenStakedAt[tokenIds[i]] = block.timestamp;
            }
        }
        _mint(msg.sender, totalToken);
        return totalToken;
    }

    // Show Staked NFTs
    function getTokensOwnedByUser(address user) public view returns(uint[] memory){
        uint256[] memory tokenStaked = INFT(nft).walletOfOwner(address(this));
        uint256[] memory tokenOwnedByUser = new uint256[](tokenStaked.length);
        uint256 currentIndex = 0;

        for (uint i; i < tokenStaked.length;){
            if(user == tokenOwnerOf[tokenStaked[i]]){
                tokenOwnedByUser[currentIndex] = tokenStaked[i];
                currentIndex++;
            }
            unchecked {++i;}
        }

        return tokenOwnedByUser;
    }

    modifier checkStake(uint256[] memory tokenId){
        for(uint256 i=0 ; i<tokenId.length; i++){
            require(tokenOwnerOf[tokenId[i]] == msg.sender, "You can't unstake");
        }
        _;
    }


    //Martian contract------------------------------------------------------------------------------------ 


    function stakeMartian(uint256 tokenId) external {
        IERC721(martianNft).safeTransferFrom(msg.sender, address(this), tokenId);
        tokenOwnerOfMartian[tokenId] = msg.sender;
        tokenStakedAtMartian[tokenId] = block.timestamp;
    }

    // Calculate Staked Tokens for a Specific martianNft
    function calculateTokensMartian(uint256 tokenId) public view returns (uint256) {
        require(tokenStakedAtMartian[tokenId] > 0, "Token Not Staked");
        uint256 timeElapsed = block.timestamp - tokenStakedAtMartian[tokenId];
        return timeElapsed * MARTIAN_EMISSION_RATE;
    }

    // Unstake Function
    function unstakeMartian(uint256 tokenId) external {
        require(tokenOwnerOfMartian[tokenId] == msg.sender, "You can't unstake");
        _mint(msg.sender, calculateTokensMartian(tokenId)); // Minting the tokens for staking
        IERC721(martianNft).transferFrom(address(this), msg.sender, tokenId);
        delete tokenOwnerOfMartian[tokenId];
        delete tokenStakedAtMartian[tokenId];
    }

    // Batch Staking of martianNfts Function
    function batchStakeMartian(uint256[] memory tokenId) external returns (bool status){
        uint256 len = tokenId.length;
        for(uint256 i=0 ; i<len; i++){
            IERC721(martianNft).safeTransferFrom(msg.sender, address(this), tokenId[i]);
            tokenOwnerOfMartian[tokenId[i]] = msg.sender;
            tokenStakedAtMartian[tokenId[i]] = block.timestamp;
        }
        return true;
    }

    // Batch Unstaking of martianNfts Function
    function batchUnstakeMartian(uint256[] memory tokenId) external checkStakeMartian(tokenId) returns (bool status){
        _mint(msg.sender, batchCalculateTokensMartian(tokenId)); // Minting the tokens for staking
        for(uint256 i=0 ; i<tokenId.length; i++){
            IERC721(martianNft).transferFrom(address(this), msg.sender, tokenId[i]);
            delete tokenOwnerOfMartian[tokenId[i]];
            delete tokenStakedAtMartian[tokenId[i]];
        }
        return true;
    }

    // Calculate total tokens of all martianNfts to unstake function
    function batchCalculateTokensMartian(uint256[] memory tokenId) public view returns (uint256) {
        uint256 totalToken;
        for(uint256 i=0 ; i<tokenId.length; i++){
            if(tokenStakedAtMartian[tokenId[i]] > 0){
                uint256 timeElapsed = block.timestamp - tokenStakedAtMartian[tokenId[i]];
                totalToken += timeElapsed * MARTIAN_EMISSION_RATE;
            }  
        }        
        return totalToken;
    }

        //show yield of a user function
    function showYieldMartian(address user) public view returns(uint256) {
        uint[] memory tokenIds = getTokensOwnedByUserMartian(user);
        if (tokenIds.length > 0){
            return batchCalculateTokensMartian(tokenIds);
        }
        return 0;        
    }

    // withdraw yield without unstaking martianNft function
    function withdrawYieldMartian(address user) external returns(uint256) {
        require(user == msg.sender, "You can't withdraw tokens");
        uint[] memory tokenIds = getTokensOwnedByUserMartian(user);
        uint256 totalToken;
        for(uint256 i=0; i<tokenIds.length ; i++){
            if(tokenStakedAtMartian[tokenIds[i]] > 0){
                uint256 timeElapsed = block.timestamp - tokenStakedAtMartian[tokenIds[i]];
                totalToken += timeElapsed * MARTIAN_EMISSION_RATE;
                tokenStakedAtMartian[tokenIds[i]] = block.timestamp;
            }
        }
        _mint(msg.sender, totalToken);
        return totalToken;
    }

    // Show Staked martianNfts
    function getTokensOwnedByUserMartian(address user) public view returns(uint[] memory){
        uint256[] memory tokenOwnedByUser = new uint256[](1112);
        uint256 currentIndex = 0;

        for(uint256 i=0; i < 1112; i++){
            if(user == tokenOwnerOfMartian[i]){
                tokenOwnedByUser[currentIndex] = i;
                currentIndex++;
            }
        }
        uint256[] memory tokenOwnedByUserFinal = new uint256[](currentIndex);

        for(uint256 i=0; i<currentIndex; i++){
            tokenOwnedByUserFinal[i] = tokenOwnedByUser[i];
        }
        return tokenOwnedByUserFinal;
    }

    modifier checkStakeMartian(uint256[] memory tokenId){
        for(uint256 i=0 ; i<tokenId.length; i++){
            require(tokenOwnerOfMartian[tokenId[i]] == msg.sender, "You can't unstake");
        }
        _;
    }


}
