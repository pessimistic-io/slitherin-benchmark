// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

import "./SafeERC20.sol";
import "./Interfaces.sol";

/**
 * @author Heisenberg
 * @title Buffer SettlementFeeDistributor
 * @notice Distributes the SettlementFee Collected by the Buffer Protocol
 */

contract SettlementFeeDistributor
{
    using SafeERC20 for ERC20;
    
    address public bfrDistributor;
    address public blpDistributor;
    ERC20 public tokenX; 

    constructor(
        ERC20 _tokenX,
        address _bfrDistributor,
        address _blpDistributor
    ) {
        tokenX = _tokenX;
        bfrDistributor = _bfrDistributor;
        blpDistributor = _blpDistributor;
    }

    function distribute() external {
        uint256 contractBalance = tokenX.balanceOf(address(this));

        if(contractBalance > 10 * (10 ** tokenX.decimals())){
            uint256 bfrAmount = (contractBalance * 4000) / 10000;
            uint256 blpAmount = contractBalance - bfrAmount;
            tokenX.safeTransfer(bfrDistributor, bfrAmount);
            tokenX.safeTransfer(blpDistributor, blpAmount);
        }
    }
}
