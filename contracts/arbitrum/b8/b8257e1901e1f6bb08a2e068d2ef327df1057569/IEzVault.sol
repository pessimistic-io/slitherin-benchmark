// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEzVault {
  //token type
  enum TYPE{
    A,
    B
  }

  /**
  * @notice              Investors purchasing aToken or bToken
  * @param type_         0 represent aToken,1 represent bToken
  * @param channel_      0 represent 0x,1 represent 1inch
  * @param quotes_       Request parameters
  */
  function purchase(TYPE type_,uint8 channel_,bytes[] calldata quotes_) external;

  /**
  * @notice              Investors redeem aToken or bToken
  * @param type_         0 represent aToken,1 represent bToken
  * @param channel_      0 represent 0x,1 represent 1inch
  * @param qty_          Redemption amount
  * @param token_        The token to be returned
  * @param quote_        Request parameters
  */
  function redeem(TYPE type_,uint8 channel_,uint256 qty_,address token_,bytes calldata quote_) external;

  /**
  * @notice               The total reserve net value of the vault = the total reserve amount * the current reserve coin price + pooledA
  * @return uint256       The total reserve net value of the vault
  */
  function totalNetWorth() external view returns(uint256);

  /**
  * @notice               The daily interest rate of aToken (9/10 of the total daily interest rate)
  */
  function interestRate() external view returns(uint256);

  /**
  * @notice           Leverage Ratio = aToken Paired Funds / bToken Paired Funds + 1
  * @return uint256   Leverage Ratio of bToken
  */
  function leverage() external view returns(uint256);

  /**
  * @notice           Get downward rebase price of bToken
  * @return uint256   downward rebase price of bToken
  */
  function convertDownPrice() external view returns(uint256);

  /**
  * @notice           Get matched funds
  * @return uint256
  */
  function matchedA() external view returns(uint256);

  /**
  * @notice           Get unmatched funds
  * @return uint256
  */
  function pooledA() external view returns(uint256);
}

