pragma solidity 0.8.4;

import "./Ownable.sol";
import "./IERC721.sol";
import "./IERC20.sol";
import "./AIAkita.sol";

contract Airdrop is Ownable {

    struct AirdropTypes{
        uint256 referral;
        uint256 akita;
        uint256 og;
        uint256 spaceid;
    }
    
    mapping(address => uint256) public claimableAmountForOgs;
    mapping(uint256 => bool) public isNFTRewardClaimed;
    mapping(uint256 => uint256) public nftTypeRewards;
    mapping(uint256 => bool) public isSpaceIdRewardClaimed;
    mapping(address => AirdropTypes) public typesAirdropClaimed;
    mapping(address => bool) isSpaceIdHolderClaimed;
    IERC20 public AiAkitaToken;
    AiAkita public AiAkitaNFT;
    IERC721 public spaceId;
    uint256 spaceIdClaimedAmount;
    
    function setTypeRewards() internal{
        uint256 decimals = 6;
        nftTypeRewards[0] = 349065850398 * 10 ** decimals;
        nftTypeRewards[1] = 392699082398 * 10 ** decimals;
        nftTypeRewards[2] = 448798950512 * 10 ** decimals;
        nftTypeRewards[3] = 523598775598 * 10 ** decimals;
        nftTypeRewards[4] = 628318530717 * 10 ** decimals;
        nftTypeRewards[5] = 758398163397 * 10 ** decimals;
        nftTypeRewards[6] = 1047197551196 * 10 ** decimals;
        nftTypeRewards[7] = 1570796326794 * 10 ** decimals;
        nftTypeRewards[8] = 3141592653589 * 10 ** decimals;
    }
    
    constructor(address AIA_, address AiAkitaNFT_, address spaceId_) {
        AiAkitaToken = IERC20(AIA_);
        AiAkitaNFT = AiAkita(AiAkitaNFT_);
        spaceId = IERC721(spaceId_);
        setTypeRewards();
        spaceIdClaimedAmount = 0;
    }

    function setRecipents(address[] calldata recipents, uint256[] calldata amounts) external onlyOwner{
        require(recipents.length == amounts.length, "Recipents length must be equal to amounts length!");        
        
        for(uint i=0; i<recipents.length; i++){
            require(claimableAmountForOgs[recipents[i]] == 0, "Recipent already set!");
            require(recipents[i] != address(0), "Can not set zero address!");
            claimableAmountForOgs[recipents[i]] = amounts[i];
            
        }
        
    }

    function claim(address referrer, uint256[] memory AiAkitaTokenIds, uint256[] memory spaceIdTokenIds) public {
        
        if(AiAkitaTokenIds.length > 0){
            claimForAkitaHolders(AiAkitaTokenIds, referrer);
        }

        if(spaceId.balanceOf(msg.sender) > 0 && spaceIdTokenIds.length > 0){
            claimForSpaceIdHolders(spaceIdTokenIds[0], referrer);
        }

        if(claimableAmountForOgs[msg.sender] > 0){
            claimForOgs(referrer);
        }
        
    }

    function claimForAkitaHolders(uint256[] memory tokenIds, address referrer) internal{
        uint256 amountToClaim = 0;
        for(uint i=0; i<tokenIds.length; i++){
            require(AiAkitaNFT.ownerOf(tokenIds[i]) == msg.sender, "You are not the owner!!");
            require(isNFTRewardClaimed[tokenIds[i]] == false, "Already claimed!");
            amountToClaim = amountToClaim + nftTypeRewards[uint256(AiAkitaNFT.nftType(tokenIds[i]))];
            isNFTRewardClaimed[tokenIds[i]] = true;
            typesAirdropClaimed[msg.sender].akita = typesAirdropClaimed[msg.sender].akita + 1;
        }
        AiAkitaToken.transfer(msg.sender, amountToClaim);
        sendReferrerRewards(referrer, amountToClaim);
    }

    function claimForSpaceIdHolders(uint256 tokenId, address referrer) internal{
        require(spaceIdClaimedAmount < 30000, "Reached limits for spaceId holders!");
        
        uint256 spaceIdHoldersRewards = 523598775598 * 10 ** 6;
        require(spaceId.ownerOf(tokenId) == msg.sender, "Must be owner of token!");
        require(isSpaceIdRewardClaimed[tokenId] == false, "Already claimed!");
        require(isSpaceIdHolderClaimed[msg.sender] == false, "Already claimed rewards!");
        
        isSpaceIdRewardClaimed[tokenId] = true;
        isSpaceIdHolderClaimed[msg.sender] = true;
        spaceIdClaimedAmount++;
        
        AiAkitaToken.transfer(msg.sender, spaceIdHoldersRewards);
        sendReferrerRewards(referrer, spaceIdHoldersRewards);
        typesAirdropClaimed[msg.sender].spaceid = typesAirdropClaimed[msg.sender].spaceid + 1;
    }

    function claimForOgs(address referrer) internal{
        uint256 amount = claimableAmountForOgs[msg.sender];
        
        require(amount > 0, "Nothing to claim!");
        claimableAmountForOgs[msg.sender] = 0;

        AiAkitaToken.transfer(msg.sender, amount);
        sendReferrerRewards(referrer, amount);
        typesAirdropClaimed[msg.sender].og = typesAirdropClaimed[msg.sender].og + 1;
    }

    function sendReferrerRewards(address referrer, uint256 totalAmount) internal {
        if(referrer != address(0) && referrer != msg.sender) {
            uint256 referralAmount = totalAmount / 10;
            AiAkitaToken.transfer(referrer, referralAmount);
            typesAirdropClaimed[referrer].referral = typesAirdropClaimed[referrer].referral + 1;
        }
    }

    function transferTokens(address to, uint256 amount) external onlyOwner{
        require(to != address(0), "Address zero!");
        AiAkitaToken.transfer(to, amount);
    }

    function userAllocation(address user, uint256[] memory AiAkitaTokenIds, uint256[] memory spaceIdTokenIds) public view returns(uint){
        uint256 totalAmount = 0;
        if(AiAkitaTokenIds.length > 0) {
            for(uint i=0; i<AiAkitaTokenIds.length; i++){
                require(AiAkitaNFT.ownerOf(AiAkitaTokenIds[i]) != address(0), "URI query for nonexistent token");
                if(isNFTRewardClaimed[AiAkitaTokenIds[i]]==false){
                totalAmount = totalAmount + nftTypeRewards[uint256(AiAkitaNFT.nftType(AiAkitaTokenIds[i]))];
                }
            }
        }
        if(spaceIdTokenIds.length>0 && isSpaceIdRewardClaimed[spaceIdTokenIds[0]]==false){
            totalAmount = totalAmount + 523598775598 * 10 ** 6;
        }
        if(claimableAmountForOgs[user]>0){
            totalAmount = totalAmount + claimableAmountForOgs[user];
        }
        return totalAmount;
    }

    function userAllocationForAiAkita(address user, uint256[] memory AiAkitaTokenIds) public view returns(uint256){
        uint totalAmount = 0;
        if(AiAkitaTokenIds.length > 0) {
            for(uint i=0; i<AiAkitaTokenIds.length; i++){
                require(AiAkitaNFT.ownerOf(AiAkitaTokenIds[i]) != address(0), "URI query for nonexistent token");
                if(isNFTRewardClaimed[AiAkitaTokenIds[i]]==false){
                totalAmount = totalAmount + nftTypeRewards[uint256(AiAkitaNFT.nftType(AiAkitaTokenIds[i]))];
                }
            }
        }
        return totalAmount;
    }

    function userAllocationForSpaceId(address user, uint256[] memory spaceIdTokenIds) public view returns(uint256) {
        uint256 totalAmount=0;
        if(spaceIdTokenIds.length>0 && isSpaceIdRewardClaimed[spaceIdTokenIds[0]]==false){
            totalAmount = totalAmount + 523598775598 * 10 ** 6;
        }
        return totalAmount;
    }

    function setTokenAddresses(address AiAkitaNFT_, address AiAkitaToken_, address spaceId_) external onlyOwner{
        AiAkitaNFT = AiAkita(AiAkitaNFT_);
        AiAkitaToken = IERC20(AiAkitaToken_);
        spaceId = IERC721(spaceId_);
    }

}
