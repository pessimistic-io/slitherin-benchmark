// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./SafeERC20Upgradeable.sol";
import "./TestDataTypes.sol";
import "./ITestHub.sol";


contract TestAPool {

    function swapWETH(
        address _hubAddress,
        address _collateral,
        uint256 _amountIn,
        TestDataTypes.SwapParams calldata _swapParams
    ) external returns (uint256) {
        //transfer collateral to ERDHub contract
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(_collateral), _hubAddress, _amountIn);
        return
            ITestHub(_hubAddress).swap(
                _collateral,
                _amountIn,
                _swapParams
            );
    }

    function transfer(address _collateral, address _to, uint _amount) public {
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(_collateral), _to, _amount);
    }

    function approve(address _collateral, address _spender) public {
        IERC20Upgradeable(_collateral).approve(_spender, type(uint256).max);
    }

    

}
