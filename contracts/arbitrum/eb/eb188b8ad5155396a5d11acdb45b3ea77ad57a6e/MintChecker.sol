// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ISolidlyRouter.sol";
import "./ISolidlyPair.sol";
import "./console.sol";

contract MintChecker is Initializable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  // Routes
  ISolidlyRouter.Routes[] public outputToLiquidRoute;
  address public dystRouter;
  address public token;
  address public liquidToken;
  address public treasury;

  function initialize(
    ISolidlyRouter.Routes[] memory _outputToLiquidRoute,
    address _dystRouter,
    address _token,
    address _liquidToken,
    address _treasury
  ) external initializer {
    for (uint256 i; i < _outputToLiquidRoute.length; ++i) {
      outputToLiquidRoute.push(_outputToLiquidRoute[i]);
    }

    dystRouter = _dystRouter;
    token = _token;
    liquidToken = _liquidToken;
    treasury = _treasury;
    __Ownable_init_unchained();
  }

  function shouldMint() public view returns (bool) {
    uint256 _in = 10**18;
    (uint256 peg, ) = ISolidlyRouter(dystRouter).getAmountOut(_in, token, liquidToken);

    if (_in > peg) {
        return true;
    } else {
      return false;
    }
  }

  function swap(
    address _oneInchRouter,
    bytes calldata _data,
    uint256 _amount
  ) public {
    require(msg.sender == liquidToken, "Only Staker can call this function");
    _swapTokenVia1inch(_oneInchRouter, _data, _amount);
  }

  /**
   * @notice Swap a token using the 1inch exchange.
   * @param _oneInchRouter The address of the 1inch router contract.
   * @param data The data payload to pass to the 1inch router contract.
   * @dev The `approve` function of the token contract is called with the `_oneInchRouter`
   * address as the spender and the maximum possible value of `uint256` as the amount.
   * @dev The `call` function of the 1inch router contract is called with the `data` payload. If
   * the call is unsuccessful, an error message is thrown.
   * @dev The `approve` function of the token contract is called with the `_oneInchRouter` address
   * as the spender and 0 as the amount.
   */
  function _swapTokenVia1inch(
    address _oneInchRouter,
    bytes calldata data,
    uint256 _amount
  ) internal {
    console.log("_swapTokenVia1inch");
    IERC20Upgradeable(token).safeTransferFrom(liquidToken, address(this), _amount);
    require(IERC20Upgradeable(token).balanceOf(address(this)) >= _amount, "residual token balance");
    IERC20Upgradeable(token).safeApprove(_oneInchRouter, _amount);
    (bool success, ) = _oneInchRouter.call(data);
    require(success, "1inch swap unsucessful");
    IERC20Upgradeable(token).safeApprove(_oneInchRouter, 0);
    uint256 _balance = IERC20Upgradeable(liquidToken).balanceOf(address(this));
    uint256 _balanceOfToken = IERC20Upgradeable(token).balanceOf(address(this));
    console.log("_balance", _balance);
    console.log("_balanceOfToken", _balanceOfToken);
    require(_balance > 0, "no tokens");
    IERC20Upgradeable(liquidToken).safeTransfer(liquidToken, _balance);
    IERC20Upgradeable(token).safeTransfer(treasury, _balanceOfToken);
  }
}

