// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

import "./SwapState.sol";
import "./SwapStructs.sol";

/**
 * @title SwapSetters
 */
contract SwapSetters is SwapState, AccessControl {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    using SafeMath for uint256;
    
    function withdrawIfAnyEthBalance(address payable receiver) external returns (uint256) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not a admin");
        uint256 balance = address(this).balance;
        receiver.transfer(balance);
        return balance;
    }
    
    function withdrawIfAnyTokenBalance(address contractAddress, address receiver) external returns (uint256) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not a admin");
        IERC20 token = IERC20(contractAddress);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(receiver, balance);
        return balance;
    }


    function setFeeCollector(address _feeCollector) internal {
        require(_feeCollector != address(0), "Atlas Dex: Fee Collector Invalid");         
        FEE_COLLECTOR = _feeCollector;
    }

    function setNativeWrappedAddress(address _nativeWrapped) internal {
        require(_nativeWrapped != address(0), "Atlas Dex: _nativeWrapped Invalid");         
        NATIVE_WRAPPED_ADDRESS = _nativeWrapped;
    }

    function set1InchRouter(address _1inchRouter) internal {
        require(_1inchRouter != address(0), "Atlas Dex: _1inchRouter Invalid");         
        oneInchAggregatorRouter = _1inchRouter;
    }

    function set0xRouter(address _0xRouter) internal {
        require(_0xRouter != address(0), "Atlas Dex: _0xRouter Invalid");         
        OxAggregatorRouter = _0xRouter;
    }

    function setInitialized(address implementation) internal {
        initializedImplementations[implementation] = true;
    }
} // end of class
