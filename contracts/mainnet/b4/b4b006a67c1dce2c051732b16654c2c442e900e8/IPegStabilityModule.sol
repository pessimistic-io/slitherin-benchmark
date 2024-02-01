// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20_IERC20.sol";
import "./IERC20BurnableMintable.sol";
import "./ITreasury.sol";

interface IPegStabilityModule {
  function treasury() external view returns (ITreasury);

  function externalStablecoin() external view returns (IERC20);

  function bluStablecoin() external view returns (IERC20BurnableMintable);

  function ratio() external view returns (uint256);

  function feesIn() external view returns (uint256);

  function feesOut() external view returns (uint256);

  function debtCeiling() external view returns (uint256);

  function totalDebt() external view returns (uint256);

  function swap(address recipient, bool toBluStablecoin)
    external
    returns (uint256 amountOut);

  function getBluStablecoinsOut(uint256 amountIn)
    external
    view
    returns (uint256 amountOut);

  function getBluStablecoinsIn(uint256 amountOut)
    external
    view
    returns (uint256 amountIn);

  function getExternalStablecoinsOut(uint256 amountIn)
    external
    view
    returns (uint256 amountOut);

  function getExternalStablecoinsIn(uint256 amountOut)
    external
    view
    returns (uint256 amountIn);

  function setFeesIn(uint256 _feesIn) external;

  function setFeesOut(uint256 _feesOut) external;

  function rescueFunds(IERC20 token, uint256 amount) external;

  function increaseDebtCeiling(uint256 amount) external;

  function decreaseDebtCeiling(uint256 amount) external;

  function setDebtCeiling(uint256 amount) external;

  event UpdatedFeesIn(uint256 feesIn);

  event UpdatedFeesOut(uint256 feesOut);

  event Swap(
    address indexed recipient,
    bool indexed toBluStablecoin,
    uint256 amountIn,
    uint256 amountOut
  );

  event UpdatedDebtCeiling(uint256 debtCeiling);
}

