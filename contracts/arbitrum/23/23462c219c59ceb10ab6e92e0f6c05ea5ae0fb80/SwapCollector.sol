// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./AggregatorV3Interface.sol";
//import "hardhat/console.sol";

contract SwapCollectorUpgradeable is Initializable{
  struct ParsedQuoteData {
    address sellToken;
    address buyToken;
    uint256 sellAmount;
    uint256 buyAmount;
  }
  using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
  bytes4 internal constant SWAP_SELECTOR = 0x36e57cb7;   //bytes4(keccak256("notSwap(address,address,uint256)"))
  //0x Switching Router
  address internal constant ZEROEX_ADDRESS = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
  bytes4 internal constant ZEROEX_SWAP_SELECTOR = 0x415565b0;
  //1inch Switching Router
  address internal constant ONEINCH_ADDRESS = 0x1111111254EEB25477B68fb85Ed929f73A960582;
  bytes4 internal constant ONEINCH_SWAP_SELECTOR = 0x12aa3caf;
  //Error Message Constant
  string internal constant CANNOT_BE_ZERO = "SwapCollector: Cannot be zero";
  string internal constant WRONG_FUNC_CALL = "SwapCollector: Wrong function call";

  function __SwapCollector_init() internal onlyInitializing {
    __SwapCollector_init_unchained();
  }

  function __SwapCollector_init_unchained() internal onlyInitializing {
  }

  /**
  * @notice               Trading Method
  * @param channel        Trading Channel(0 represent 0x,1 represent 1inch)
  * @param quote          Request Parameters
  * @return uint256       Transaction Return Quantity
  */
  function _swap(uint8 channel,bytes calldata quote,address sellToken,uint256 sellAmount) internal returns (uint256){
    if(channel==0){
      IERC20MetadataUpgradeable(sellToken).safeIncreaseAllowance(ZEROEX_ADDRESS,sellAmount);
      return _zeroExSwap(quote);
    }else if(channel==1){
      IERC20MetadataUpgradeable(sellToken).safeIncreaseAllowance(ONEINCH_ADDRESS,sellAmount);
      return _oneInchSwap(quote);
    }else{
      revert("SwapCollector: Wrong Parameter");
    }
  }

  function parseQuoteData(uint8 channel,bytes calldata quote) public pure returns (ParsedQuoteData memory parsedQuoteData){
    bytes4 selector = _bytesToBytes4(quote[:4]);
    if(selector==SWAP_SELECTOR){
      (address sellToken,address buyToken, uint256 sellAmount) = abi.decode(quote[4:],(address,address,uint256));
      parsedQuoteData.sellToken = sellToken;
      parsedQuoteData.buyToken = buyToken;
      parsedQuoteData.sellAmount = sellAmount;
      parsedQuoteData.buyAmount = 0;
    }else{
      if(channel==0){
        (address sellToken, address buyToken, uint256 sellAmount,uint256 buyAmount) = _parseZeroExData(quote);
        parsedQuoteData.sellToken = sellToken;
        parsedQuoteData.buyToken = buyToken;
        parsedQuoteData.sellAmount = sellAmount;
        parsedQuoteData.buyAmount = buyAmount;
      }else if(channel==1){
        (address sellToken, address buyToken, uint256 sellAmount,uint256 buyAmount) = _parseOneInchData(quote);
        parsedQuoteData.sellToken = sellToken;
        parsedQuoteData.buyToken = buyToken;
        parsedQuoteData.sellAmount = sellAmount;
        parsedQuoteData.buyAmount = buyAmount;
      }else{
        revert("SwapCollector: Wrong Parameter");
      }
    }
  }

  /**
  * @notice               Trade with 0x
  * @param quote          Request Parameters
  */
  function _zeroExSwap(bytes calldata quote) internal returns (uint256){
    (bool success,bytes memory data) = ZEROEX_ADDRESS.call(quote);
    (uint256 buyAmount) = abi.decode(data,(uint256));
    require(success, '0x-swap-failed');
    return buyAmount;
  }

  function _parseZeroExData(bytes calldata data) internal pure returns (address sellToken, address buyToken, uint256 sellAmount,uint256 buyAmount){
    bytes4 selector = _bytesToBytes4(data[:4]);
    require(selector==ZEROEX_SWAP_SELECTOR,WRONG_FUNC_CALL);
    (sellToken, buyToken, sellAmount,buyAmount) = abi.decode(data[4:],(address,address,uint256,uint256));
  }

  /**
  * @notice               Trade with 1inch
  * @param quote          Request Parameters
  */
  function _oneInchSwap(bytes calldata quote) internal returns (uint256) {
    (bool success, bytes memory data) = ONEINCH_ADDRESS.call(quote);
    (uint256 buyAmount,) = abi.decode(data, (uint256, uint256));
    if (!success) revert("1Inch-swap-failed");
    return buyAmount;
  }

  function _parseOneInchData(bytes calldata data) internal pure returns (address sellToken, address buyToken, uint256 sellAmount,uint256 buyAmount){
    bytes4 selector = _bytesToBytes4(data[:4]);
    require(selector==ONEINCH_SWAP_SELECTOR,WRONG_FUNC_CALL);
    (,sellToken,buyToken,,,sellAmount,buyAmount) = abi.decode(data[4:],(address,address,address,address,address,uint256,uint256));
  }

  function _bytesToBytes4(bytes memory input) internal pure returns(bytes4 output){
    assembly {
      output := mload(add(input, 32))
    }
  }

  uint256[50] private __gap;

}

