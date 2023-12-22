// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import { IBasePermit2Adapter, IPermit2 } from "./IBasePermit2Adapter.sol";
import { Token } from "./Token.sol";

/**
 * @title Base Permit2 Adapter
 * @author Sam Bugs
 * @notice The base contract for Permit2 adapters
 */
abstract contract BasePermit2Adapter is IBasePermit2Adapter {
  /// @inheritdoc IBasePermit2Adapter
  address public constant NATIVE_TOKEN = Token.NATIVE_TOKEN;
  /// @inheritdoc IBasePermit2Adapter
  // solhint-disable-next-line var-name-mixedcase
  IPermit2 public immutable PERMIT2;

  constructor(IPermit2 _permit2) {
    PERMIT2 = _permit2;
  }

  // solhint-disable-next-line no-empty-blocks
  receive() external payable { }

  modifier checkDeadline(uint256 _deadline) {
    if (block.timestamp > _deadline) revert TransactionDeadlinePassed(block.timestamp, _deadline);
    _;
  }
}

