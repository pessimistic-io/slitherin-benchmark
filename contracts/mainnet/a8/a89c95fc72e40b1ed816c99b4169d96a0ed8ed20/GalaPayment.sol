// SPDX-License-Identifier: MIT 
pragma solidity 0.8.2;

import "./UpgradeableBase.sol";
import "./MessageValidator.sol";
import "./IGalaGameItems.sol";
import "./IGalaERC20.sol";
import "./AddressUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";


contract GalaPayment is UpgradeableBase, MessageValidator
{    
    event PaymentTransferExecuted(string orderId, address token, uint amount,uint transBlock, address wallet); 
    event PaymentBurnExecuted(string orderId, address token, uint amount,uint transBlock);
    event PaymentBurnErc1155Executed(string orderId, address token, uint baseId, uint amount, uint transBlock);
    event PaymentExecuted (string orderId,uint amount,uint transBlock, address wallet);    
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address public constant DEAD_ADDRESS = address(0);     

    modifier isValidToken(address _token)
    {
        require(_token != DEAD_ADDRESS, "Token address cannot be zero");
        _;
    }

    function initialize() initializer external
    {         
        init();        
    } 
    
    function payAndTransferERC20(PaymentMessage calldata params)   
    isValidWallet(params.wallet)
    isValidMessage(params)
    isValidBlock(params.transBlock)    
    isValidOrder(params.orderId)
    isValidToken(params.token)    
    nonReentrant
    whenNotPaused
    external payable
    {   
        address wallet = params.wallet == address(0) ? galaWallet : params.wallet;
        emit PaymentTransferExecuted(params.orderId,params.token,params.amount,params.transBlock, wallet);           
        IERC20Upgradeable(params.token).safeTransferFrom(msg.sender, address(wallet), params.amount); 
    }      

    function payAndBurnERC20(PaymentMessage calldata params)       
    isValidMessage(params)
    isValidBlock(params.transBlock)    
    isValidOrder(params.orderId)
    isValidToken(params.token)
    nonReentrant
    whenNotPaused
    external 
    {   
        emit PaymentBurnExecuted(params.orderId,params.token,params.amount,params.transBlock);   
        IGalaERC20(params.token).burnFrom(msg.sender, params.amount);   
    }      

    function payETH(PaymentMessageEth calldata params)
    isValidWallet(params.wallet) 
    isValidMessageForEth(params)
    isValidBlock(params.transBlock)    
    isValidOrder(params.orderId)    
    nonReentrant   
    whenNotPaused 
    external payable
    {   
        address wallet = params.wallet == address(0) ? galaWallet : params.wallet;
        emit PaymentExecuted(params.orderId, msg.value, params.transBlock, wallet);     
        payable(address(wallet)).sendValue(msg.value);
    }

    function payAndBurnErc1155(PaymentMessageErc1155 calldata params)       
    isValidMessageForErc1155(params)
    isValidBlock(params.transBlock)    
    isValidOrder(params.orderId)
    isValidToken(params.token)
    nonReentrant
    whenNotPaused
    external 
    {  
        uint256[] memory baseIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        baseIds[0] = params.baseId;
        amounts[0] = params.amount;
        emit PaymentBurnErc1155Executed(params.orderId, params.token, params.baseId, params.amount, params.transBlock);   
        IGalaGameItems(params.token).burn(msg.sender, baseIds, amounts);        
    }      

     function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }      
}


