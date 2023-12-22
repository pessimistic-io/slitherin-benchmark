// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { IHatsToggle } from "./IHatsToggle.sol";
import { IHats } from "./IHats.sol";
import { HatsToggleModule, HatsModule } from "./HatsToggleModule.sol";

contract SeasonToggle is HatsToggleModule {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Thrown when a non-admin attempts to extend a branch to a new season
  error SeasonToggle_NotBranchAdmin();
  /// @notice Thrown when attempting to extend a branch to a new season before its extendable
  error SeasonToggle_NotExtendable();
  /// @notice Valid extension delays are <= 10,000
  error SeasonToggle_InvalidExtensionDelay();
  /// @notice Season durations must be at least `MIN_SEASON_DURATION` long
  error SeasonToggle_SeasonDurationTooShort();

  /*//////////////////////////////////////////////////////////////
                                EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when `_branchRoot` has been extended to a new season
  event Extended(uint256 _branchRoot, uint256 _duration, uint256 _extensionDelay);

  /*//////////////////////////////////////////////////////////////
                          PUBLIC  CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their locations. In this module, all are inherited from HatsModule.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * --------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                           |
   * --------------------------------------------------------------------|
   * Offset  | Constant        | Type    | Length  | Source Contract     |
   * --------------------------------------------------------------------|
   * 0       | IMPLEMENTATION  | address | 20      | HatsModule          |
   * 20      | HATS            | address | 20      | HatsModule          |
   * 40      | hatId           | uint256 | 32      | HatsModule          |
   * --------------------------------------------------------------------+
   */

  /// @notice The minimum length of a season, in seconds
  uint256 public constant MIN_SEASON_DURATION = 1 hours; // 1 hour = 3,600 seconds

  /*//////////////////////////////////////////////////////////////
                          INTERNAL  CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The divisor used to calculate the extension delay proportion given an `extensionDelay` numerator
   * @dev This value is >>100 to allow for fine-grained delay values without introducing significant rounding artifacts
   * from uint division
   */
  uint256 internal constant DELAY_DIVISOR = 10_000;

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @notice The final second of the current season (a unix timestamp), i.e. the point at which hats become inactive
  uint256 public seasonEnd;
  /// @notice The length of the current season, in seconds
  uint256 public seasonDuration;

  /**
   * @notice The proportion of the current season that must elapse before the branch can be extended to another season.
   * @dev Stored in the form of `x` in the expression `x / 10,000`. Here are some sample values:
   *   - 0      ⇒ none of the current season must have passed before another season can be added
   *   - 5,000  ⇒ 50% of the current season must have passed before another season can be added
   *   - 10,000 ⇒ 100% of the current season must have passed before another season can be added
   */
  uint256 public extensionDelay;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets up this instance with initial operational values
   * @dev Only callable by the factory. Since the factory only calls this function during a new deployment, this ensures
   * it can only be called once per instance, and that the implementation contract is never initialized.
   * @param _initData Packed initialization data with two parameters:
   *  _seasonDuration - The length of the season, in seconds. Must be >= 1 hour (`3600` seconds).
   *  _extensionDelay - The proportion of the season that must elapse before the branch can be extended
   * for another season. The value is treated as the numerator `x` in the expression `x / 10,000`, and therefore must be
   * <= 10,000.
   */
  function _setUp(bytes calldata _initData) internal override {
    (uint256 _seasonDuration, uint256 _extensionDelay) = abi.decode(_initData, (uint256, uint256));
    // prevent invalid extension delays
    if (_extensionDelay > DELAY_DIVISOR) revert SeasonToggle_InvalidExtensionDelay();
    // season duration must be non-zero, otherwise
    if (_seasonDuration < MIN_SEASON_DURATION) revert SeasonToggle_SeasonDurationTooShort();
    // initialize the mutable state vars
    seasonDuration = _seasonDuration;
    extensionDelay = _extensionDelay;
    // seasonEnd = block.timestamp + _seasonDuration;
    seasonEnd = block.timestamp + _seasonDuration;
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the SeasonToggle implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory __version) HatsModule(__version) { }

  /*//////////////////////////////////////////////////////////////
                          HATS TOGGLE FUNCTION
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Check if a hat is active, i.e. we've not yet reached the end of the season
   * @dev This function is not expected to be called for hats outside of this SeasonToggle instance's branch. To
   * minimize gas overhead for calls for hats *within* the branch, this function does not check branch inclusion. If
   * called for a hat outside of the branch, this function will return `true`, which may not be relevant or
   * appropriate for that hat.
   * @param / The id of the hat to check. This hat should be within the branch to which this instance of
   * SeasonToggle applies; otherwise the result may not be relevant.
   * @return _active False if the season has ended; true otherwise.
   */
  function getHatStatus(uint256) public view override returns (bool _active) {
    /**
     * @dev For gas-minimization purposes, hats become inactive on the last second of the season (`seasonEnd`) rather
     * than once the entire season has elapsed. This allows us to avoid the extra opcode required to check the "equals
     * to" case, saving 3 gas. This is not much, but this function is expected to be called many times, and often many
     * times within a single transaction (e.g. when resolving hat admins within a branch that uses SeasonToggle).
     */
    _active = block.timestamp < seasonEnd;
  }

  /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Extend the branch for a new season, optionally with a new season duration. This function is typically
   * called once the toggle has already been set up, but it can also be used to set it up for the first time.
   * @dev Requires admin privileges for the branchRoot hat.
   * @param _duration [OPTIONAL] A new custom season duration, in seconds. Set to 0 to re-use the previous
   * duration.
   * @param _extensionDelay [OPTIONAL] A new delay
   */
  function extend(uint256 _duration, uint256 _extensionDelay) external {
    // prevent non-admins from extending
    if (!HATS().isAdminOfHat(msg.sender, hatId())) revert SeasonToggle_NotBranchAdmin();
    // prevent extending before extension threshold has been reached
    if (!extendable()) revert SeasonToggle_NotExtendable();
    // prevent invalid extension delays
    if (_extensionDelay > DELAY_DIVISOR) revert SeasonToggle_InvalidExtensionDelay();

    // process the optional _duration value
    uint256 duration;
    // if new, store the new value and prepare to use it for extension
    if (_duration > 0) {
      // prevent too short durations
      if (_duration < MIN_SEASON_DURATION) revert SeasonToggle_SeasonDurationTooShort();
      // store the new value; will be used to check extension for next season
      seasonDuration = _duration;
      // prepare to use it for extension
      duration = _duration;
    } else {
      // otherwise, just prepare to use the existing value from storage
      duration = seasonDuration;
    }

    // process the optional _extensionDelay value. We know a set value is valid because of the earlier check.
    if (_extensionDelay > 0) extensionDelay = _extensionDelay;

    // extend to a new season with length `duration`
    seasonEnd += duration;
    // log the extension
    emit Extended(hatId(), _duration, _extensionDelay);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Whether the expiry for this branch can be extended to another season, which is allowed if more than
   * half of the current season has elapsed
   */
  function extendable() public view returns (bool) {
    return block.timestamp >= _extensionThreshold(seasonEnd, extensionDelay, seasonDuration);
  }

  /**
   * @notice The timestamp at which the branch can be extended to another season, i.e. when it becomes {extendable}
   */
  function extensionThreshold() public view returns (uint256) {
    return _extensionThreshold(seasonEnd, extensionDelay, seasonDuration);
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The timestamp at which the branch can be extended to another season, i.e. when it becomes {extendable}
   * @param _seasonEnd The timestamp at which the next season begins, ie 1 second after the current season ends
   * @param _extensionDelay The proportion of the season that must elapse before the branch can be extended
   * for another season
   * @param _seasonDuration The length of the season, in seconds
   */
  function _extensionThreshold(uint256 _seasonEnd, uint256 _extensionDelay, uint256 _seasonDuration)
    internal
    pure
    returns (uint256)
  {
    /**
     * @dev We need to work backwards from the end of the season, so we subtract `_extensionDelay` from the
     * `DELAY_DIVISOR`; this is akin to subtracting a percentage from 1 in order to find its complement.
     */
    return (_seasonEnd - ((_seasonDuration * (DELAY_DIVISOR - _extensionDelay)) / DELAY_DIVISOR));
  }
}

