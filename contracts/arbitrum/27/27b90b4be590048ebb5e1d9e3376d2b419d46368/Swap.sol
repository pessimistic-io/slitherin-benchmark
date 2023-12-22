// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IVault.sol";
import "./IReader.sol";
import "./ISwap.sol";
import "./IDegenPool.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./AccessControlEnumerable.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract Swap is ISwap, AccessControlEnumerable {
  using SafeERC20 for IERC20;

  IVault public immutable vault;
  IReader public immutable reader;

  IERC20 public degenStableAsset;
  IWETH public immutable weth;


  constructor(address vault_, address _reader, address _admin, address _weth) {
    vault = IVault(vault_);
    reader = IReader(_reader);
    weth = IWETH(_weth);

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
     _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  function setDegenStableAsset(IERC20 _degenStableAsset) external onlyRole(DEFAULT_ADMIN_ROLE) {
    degenStableAsset = _degenStableAsset;
  }

  function swapTokens(
    uint256 _amountToSwap,
    address _fromAsset,
    address _toAsset,
    address _receiver
  ) public returns (uint256 amountReturned_, uint256 feesPaidInOut_) {
    (, feesPaidInOut_) = reader.getAmountOut(IVault(vault), _fromAsset, _toAsset, _amountToSwap);
    IERC20(_fromAsset).safeTransfer(address(vault), _amountToSwap);
    amountReturned_ = vault.swap(_fromAsset, _toAsset, _receiver);
    require(amountReturned_ > 0, "SWAP: swap failed");
    return (amountReturned_, feesPaidInOut_);
  }

  function claimLiquidatorFees(address _liquidator, address _degenPool) external {
    uint96 amount = IDegenPool(_degenPool).claimLiquidatorFeesSwap(_liquidator);
    degenStableAsset.safeTransfer(address(vault), amount);
    uint256 amountReturned_ = vault.swap(address(degenStableAsset), address(weth), address(this));
    weth.withdraw(amountReturned_);
    payable(_liquidator).transfer(amountReturned_);
  }

  function closePosition(bytes[] calldata priceData, bytes32 id, address outputToken, address _degenPool) external {
    IDegenPool degenPool = IDegenPool(_degenPool);
    require(msg.sender == degenPool.getPosition(id).player, "SWAP: not player");

    uint96 amount = degenPool.closePositionSwap(priceData, id);
    swapTokens(amount, address(degenStableAsset), outputToken, msg.sender);
  }

  receive() external payable {}

  // function that allows the admin to withdraw eth from the contract
  function withdrawEth(address payable _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _to.transfer(_amount);
  }
}

