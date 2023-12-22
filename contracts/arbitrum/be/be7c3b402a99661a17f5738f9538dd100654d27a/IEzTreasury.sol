// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISwapCollector.sol";

interface IEzTreasury {
  //子基金类型
  enum TYPE{
    A,
    B
  }

  /**
  * @notice              投资人购买aToken或bToken
  * @param type_         0为aToken,1为bToken
  * @param channel_      0为0x,1为1inch
  * @param quotes_       请求参数
  */
  function purchase(TYPE type_,uint8 channel_,SwapQuote[] calldata quotes_) external;

  /**
  * @notice              投资人赎回aToken或bToken
  * @param type_         0为aToken,1为bToken
  * @param channel_      0为0x,1为1inch
  * @param qty_          赎回数量
  * @param token_        返还的token
  * @param quote_        请求参数
  */
  function redeem(TYPE type_,uint8 channel_,uint256 qty_,address token_,SwapQuote calldata quote_) external;

  /**
  * @notice               金库总储备净值=储备币总储量*当前储备币价格+pooledA
  * @return uint256       金库总储备净值
  */
  function totalNetWorth() external view returns(uint256);

  /**
  * @notice               动态计算aToken的日利息
  */
  function interestRate() external view returns(uint256);

  /**
  * @notice           杠杆率=aToken已配对资金/bToken已配对资金+1
  * @return uint256   bToken的杠杆率
  */
  function leverage() external view returns(uint256);

  /**
  * @notice           获取bToken的下折价格
  * @return uint256   bToken的下折价格
  */
  function convertDownPrice() external view returns(uint256);

  /**
  * @notice           获取匹配的A资金
  * @return uint256
  */
  function matchedA() external view returns(uint256);

  /**
  * @notice           获取未匹配的A资金
  * @return uint256
  */
  function pooledA() external view returns(uint256);
}

