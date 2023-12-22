pragma solidity 0.8.4;

import "./Ownable.sol";
import "./IERC721.sol";
import "./IERC20.sol";


contract EarlyUsersAirdrop is Ownable {
    
    mapping(address => uint256) public claimableAmountForOgs;
    IERC20 public AiAkitaToken;
    
    constructor(address AIA_) {
        AiAkitaToken = IERC20(AIA_);
    }

    function setRecipents(address[] calldata recipents, uint256[] calldata amounts) external onlyOwner{
        require(recipents.length == amounts.length, "Recipents length must be equal to amounts length!");        
        
        for(uint i=0; i<recipents.length; i++){
            require(recipents[i] != address(0), "Can not set zero address!");
            claimableAmountForOgs[recipents[i]] = amounts[i];
            
        }
        
    }

    function claim(address referrer) public {

        if(claimableAmountForOgs[msg.sender] > 0){
            claimForOgs(referrer);
        }
        
    }


    function claimForOgs(address referrer) internal{
        uint256 amount = claimableAmountForOgs[msg.sender];
        
        require(amount > 0, "Nothing to claim!");
        claimableAmountForOgs[msg.sender] = 0;

        AiAkitaToken.transfer(msg.sender, amount);
        sendReferrerRewards(referrer, amount);
    }

    function sendReferrerRewards(address referrer, uint256 totalAmount) internal {
        if(referrer != address(0) && referrer != msg.sender) {
            uint256 referralAmount = totalAmount / 10;
            AiAkitaToken.transfer(referrer, referralAmount);
        }
    }

    function transferTokens(address to, uint256 amount) external onlyOwner{
        require(to != address(0), "Address zero!");
        AiAkitaToken.transfer(to, amount);
    }

    function userAllocation(address user, uint256[] memory AiAkitaTokenIds, uint256[] memory spaceIdTokenIds) public view returns(uint){
        uint256 totalAmount = 0;
        
        if(claimableAmountForOgs[user]>0){
            totalAmount = totalAmount + claimableAmountForOgs[user];
        }
        return totalAmount;
    }

    function setTokenAddresses(address AiAkitaToken_) external onlyOwner{
        
        AiAkitaToken = IERC20(AiAkitaToken_);
        
    }

}
