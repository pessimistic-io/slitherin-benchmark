// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IWNATIVE.sol";
import "./IOreoStableSwap.sol";

contract OreoStableSwapWNATIVEHelper is Ownable {
  using SafeERC20 for IERC20;

  uint256 public constant N_COINS = 2;
  IWNATIVE public immutable WNATIVE;

  // Record whether approved for stable swap smart contract.
  mapping(address => bool) isApproved;

  mapping(address => bool) public isWhitelist;

  error NotWNATIVEPair();
  error NotWhitelist();
  error InvalidNCOINS();

  event UpdateWhitelist(address swap, bool status);

  constructor(IWNATIVE _WNATIVE) {
    WNATIVE = _WNATIVE;
  }

  function setWhiteList(address _swap, bool _status) external onlyOwner {
    isWhitelist[_swap] = _status;
    emit UpdateWhitelist(_swap, _status);
  }

  function initSwapPair(IOreoStableSwap swap) internal {
    address token0 = swap.coins(0);
    address token1 = swap.coins(1);
    address LPToken = swap.token();
    IERC20(token0).safeApprove(address(swap), type(uint256).max);
    IERC20(token1).safeApprove(address(swap), type(uint256).max);
    IERC20(LPToken).safeApprove(address(swap), type(uint256).max);
    isApproved[address(swap)] = true;
  }

  function add_liquidity(
    IOreoStableSwap swap,
    uint256[N_COINS] memory amounts,
    uint256 min_mint_amount
  ) external payable {
    if (!isWhitelist[address(swap)]) revert NotWhitelist();
    if (swap.N_COINS() != N_COINS) revert InvalidNCOINS();
    if (!isApproved[address(swap)]) initSwapPair(swap);

    address token0 = swap.coins(0);
    address token1 = swap.coins(1);
    uint256 WNATIVEIndex;
    if (token0 == address(WNATIVE)) {
      WNATIVEIndex = 0;
    } else if (token1 == address(WNATIVE)) {
      WNATIVEIndex = 1;
    } else {
      revert NotWNATIVEPair();
    }
    require(msg.value == amounts[WNATIVEIndex], "Inconsistent quantity");
    WNATIVE.deposit{ value: msg.value }();
    if (WNATIVEIndex == 0) {
      IERC20(token1).safeTransferFrom(msg.sender, address(this), amounts[1]);
    } else {
      IERC20(token0).safeTransferFrom(msg.sender, address(this), amounts[0]);
    }
    swap.add_liquidity(amounts, min_mint_amount);

    address LPToken = swap.token();
    uint256 mintedLPAmount = IERC20(LPToken).balanceOf(address(this));
    IERC20(LPToken).safeTransfer(msg.sender, mintedLPAmount);
  }

  function remove_liquidity(
    IOreoStableSwap swap,
    uint256 _amount,
    uint256[N_COINS] memory min_amounts
  ) external {
    if (!isWhitelist[address(swap)]) revert NotWhitelist();
    if (swap.N_COINS() != N_COINS) revert InvalidNCOINS();
    if (!isApproved[address(swap)]) initSwapPair(swap);

    address token0 = swap.coins(0);
    address token1 = swap.coins(1);
    uint256 WNATIVEIndex;
    if (token0 == address(WNATIVE)) {
      WNATIVEIndex = 0;
    } else if (token1 == address(WNATIVE)) {
      WNATIVEIndex = 1;
    } else {
      revert NotWNATIVEPair();
    }
    address LPToken = swap.token();
    IERC20(LPToken).safeTransferFrom(msg.sender, address(this), _amount);
    swap.remove_liquidity(_amount, min_amounts);

    uint256 WNATIVEBalance = WNATIVE.balanceOf(address(this));
    WNATIVE.withdraw(WNATIVEBalance);
    _safeTransferNATIVE(msg.sender, address(this).balance);
    if (WNATIVEIndex == 0) {
      uint256 token1Balance = IERC20(token1).balanceOf(address(this));
      IERC20(token1).safeTransfer(msg.sender, token1Balance);
    } else {
      uint256 token0Balance = IERC20(token0).balanceOf(address(this));
      IERC20(token0).safeTransfer(msg.sender, token0Balance);
    }
  }

  function _safeTransferNATIVE(address to, uint256 value) internal {
    (bool success, ) = to.call{ gas: 2300, value: value }("");
    require(success, "TransferHelper: NATIVE_TRANSFER_FAILED");
  }

  receive() external payable {
    assert(msg.sender == address(WNATIVE)); // only accept NATIVE from the WNATIVE contract
  }
}

