// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./IJBDirectory.sol";
import "./IJBPaymentTerminal.sol";
import "./IJBSplitAllocator.sol";
import "./JBSplitAllocationData.sol";
import "./JBTokens.sol";
import "./ERC165.sol";

/**
  @notice
  Juicebox split allocator for allocating V2 treasury funds to a V3 treasury.

  @dev
  Adheres to -
  IJBSplitAllocator: Adhere to Allocator pattern to receive payout distributions for allocation. 

  @dev
  Inherits from -
  ERC165: Introspection on interface adherance. 
*/
contract V2Allocator is ERC165, IJBSplitAllocator {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error TERMINAL_NOT_FOUND();

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /**
    @notice
    The V3 directory address.
  */
  IJBDirectory public immutable directory;

  /**
    @param _directory The V3 directory address.  
  */
  constructor(IJBDirectory _directory) {
    directory = _directory;
  }

  /**
    @notice
    Allocate hook that will transfer treasury funds to V3.

    @param _data The allocation config which specifies the destination of the funds.
  */
  function allocate(JBSplitAllocationData calldata _data) external payable override {
    // Keep a reference to the ID of the project that will be receiving funds.
    uint256 _v3ProjectId = _data.split.projectId;

    // Get the ETH payment terminal for the destination project in the V3 directory.
    IJBPaymentTerminal _terminal = directory.primaryTerminalOf(_v3ProjectId, JBTokens.ETH);

    // Make sure there is an ETH terminal.
    if (address(_terminal) == address(0)) revert TERMINAL_NOT_FOUND();

    // Add the funds to the balance of the V3 terminal.
    _terminal.addToBalanceOf{value: msg.value}(
      _v3ProjectId,
      msg.value,
      JBTokens.ETH,
      'v2 -> v3 allocation',
      bytes('')
    );
  }

  function supportsInterface(bytes4 _interfaceId)
    public
    view
    override(IERC165, ERC165)
    returns (bool)
  {
    return
      _interfaceId == type(IJBSplitAllocator).interfaceId || super.supportsInterface(_interfaceId);
  }
}

