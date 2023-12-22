// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { HatsEligibilityModule, HatsModule } from "./HatsEligibilityModule.sol";

/**
 * @title HatWearingEligibility
 * @author spengrah
 * @author Haberdasher Labs
 * @notice This contract is a simple Hats Protocol eligibility module that checks if a user is wearing a specific hat.
 * @dev This contract inherits from HatsModule and is designed for minimal proxy clones to be deployed via
 * HatsModuleFactory. To work, it must be set as the eligibility module for a given hat.
 */
contract HatWearingEligibility is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                            CONSTANTS 
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their location.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * ----------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                             |
   * ----------------------------------------------------------------------|
   * Offset  | Constant          | Type    | Length  | Source              |
   * ----------------------------------------------------------------------|
   * 0       | IMPLEMENTATION    | address | 20      | HatsModule          |
   * 20      | HATS              | address | 20      | HatsModule          |
   * 40      | hatId             | uint256 | 32      | HatsModule          |
   * 72      | CRITERION_HAT     | uint256 | 32      | this                |
   * ----------------------------------------------------------------------+
   */

  /// @notice The hat that this module checks for eligibility
  function CRITERION_HAT() public pure returns (uint256) {
    return _getArgUint256(72);
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // this module has no initialization logic
  }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsEligibilityModule
  function getWearerStatus(address _wearer, uint256 /**_hatId */)// forgefmt: disable-line
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    /// @dev this module does not determine standing, so we default to good standing
    standing = true;

    eligible = HATS().isWearerOfHat(_wearer, CRITERION_HAT());
  }
}

