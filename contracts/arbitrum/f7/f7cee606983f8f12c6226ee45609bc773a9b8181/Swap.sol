// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IVault.sol";
import "./IReader.sol";
import "./ISwap.sol";
import "./IERC20.sol";


contract Swap is ISwap {

 IVault public immutable vault;
 IReader public immutable reader;

 constructor(address vault_, address _reader) {
  vault = IVault(vault_);
  reader = IReader(_reader);
 }


  function swapTokens(
    uint256 _amountToSwap,
    address _fromAsset,
    address _toAsset,
    address _receiver
  ) external returns (uint256 amountReturned_, uint256 feesPaidInOut_) {
    (, feesPaidInOut_) = reader.getAmountOut(
      IVault(vault),
      _fromAsset,
      _toAsset,
      _amountToSwap
    );
    IERC20(_fromAsset).transfer(address(vault), _amountToSwap);
    amountReturned_ = vault.swap(_fromAsset, _toAsset, _receiver);
    require(amountReturned_ > 0, "SWAP: swap to stables failed");
    return (amountReturned_, feesPaidInOut_);
  }

}
