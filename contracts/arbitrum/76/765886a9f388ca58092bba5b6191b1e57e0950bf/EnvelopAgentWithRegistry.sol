// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Ownable.sol";
import "./ServiceAgent.sol";

contract EnvelopAgentWithRegistry is ServiceAgent, Ownable {

    
    function withdrawFeeEther() external onlyOwner {
        _withdrawEther(msg.sender);
        
    }

    function withdrawFeeERC20(address _erc20) external onlyOwner {
        _withdrawTokens(_erc20, msg.sender);
    }
    

     
    
    

}
