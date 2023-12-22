// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./AggregatorV3Interface.sol";
import "./ISwapCollector.sol";
//import "hardhat/console.sol";

contract SwapCollectorUpgradeable is Initializable,ISwapCollector{
  using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
  //0x交换路由
  address internal constant ZEROEX_ADDRESS = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
  //1inch交换路由
  address internal constant ONEINCH_ADDRESS = 0x1111111254EEB25477B68fb85Ed929f73A960582;
  //报错信息常量
  string internal constant CANNOT_BE_ZERO = "SwapCollector: Cannot be zero";

  function __SwapCollector_init() internal onlyInitializing {
    __SwapCollector_init_unchained();
  }

  function __SwapCollector_init_unchained() internal onlyInitializing {
  }

  /**
  * @notice               交易方法
  * @param channel        交易渠道(0为0x,1为1inch)
  * @param quote          请求参数
  * @return uint256       交易返回数量
  */
  function swap(uint8 channel,SwapQuote calldata quote) internal returns (uint256){
    if(channel==0){
      return zeroExSwap(quote);
    }else if(channel==1){
      return oneInchSwap(quote);
    }else{
      revert("SwapCollector: Wrong Parameter");
    }
  }

  /**
  * @notice               用0x进行交易
  * @param quote          请求参数
  */
  function zeroExSwap(SwapQuote calldata quote) internal returns (uint256){
    (bool success,bytes memory data) = ZEROEX_ADDRESS.call(quote.swapCallData);
    (uint256 buyAmount) = abi.decode(data,(uint256));
    require(success, '0x-swap-failed');
    return buyAmount;
  }

  /**
  * @notice               用1inch进行交易
  * @param quote          请求参数
  */
  function oneInchSwap(SwapQuote calldata quote) internal returns (uint256) {
    (bool success, bytes memory data) = ONEINCH_ADDRESS.call(quote.swapCallData);
    (uint256 buyAmount,) = abi.decode(data, (uint256, uint256));
    if (!success) revert("1Inch-swap-failed");
    return buyAmount;
  }

  uint256[50] private __gap;

}

