// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.19;

import "./IERC20.sol";
import "./Math.sol";
import "./SafeMath.sol";
import "./GovernanceInitiationData.sol";

/**
 * @title Vesting
 * @notice A token holder contract that can release its token balance gradually like a
 * typical vesting scheme, with a cliff and vesting period.
 * @dev Modified version of https://github.com/tornadocash/torn-token/blob/master/contracts/Vesting.sol that includes a GovernanceInitiation
 * contract instance as parameter to obtain the token address.
 */
contract Vesting {
  using SafeMath for uint256;

  uint256 public constant SECONDS_PER_MONTH = 30 days;

  event Released(uint256 amount);

  // beneficiary of tokens after they are released
  address public immutable beneficiary;
  IERC20 public immutable token;

  uint256 public immutable cliffInMonths;
  uint256 public immutable startTimestamp;
  uint256 public immutable durationInMonths;
  uint256 public released;

  /**
   * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
   * _beneficiary, monthly in a linear fashion until duration has passed. By then all
   * of the balance will have vested.
   * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
   * @param _cliffInMonths duration in months of the cliff in which tokens will begin to vest
   * @param _durationInMonths duration in months of the period in which the tokens will vest
   */
  constructor(
    GovernanceInitiationData _initiationData,
    address _beneficiary,
    uint256 _startTimestamp,
    uint256 _cliffInMonths,
    uint256 _durationInMonths
  ) {
    require(_beneficiary != address(0), "Beneficiary cannot be empty");
    require(_cliffInMonths <= _durationInMonths, "Cliff is greater than duration");

    token = IERC20(_initiationData.tokenAddress());
    beneficiary = _beneficiary;
    durationInMonths = _durationInMonths;
    cliffInMonths = _cliffInMonths;
    startTimestamp = _startTimestamp == 0 ? blockTimestamp() : _startTimestamp;
  }

  /**
   * @notice Transfers vested tokens to beneficiary.
   */
  function release() external {
    uint256 vested = vestedAmount();
    require(vested > 0, "No tokens to release");

    released = released.add(vested);
    token.transfer(beneficiary, vested);

    emit Released(vested);
  }

  /**
   * @dev Calculates the amount that has already vested but hasn't been released yet.
   */
  function vestedAmount() public view returns (uint256) {
    if (blockTimestamp() < startTimestamp) {
      return 0;
    }

    uint256 elapsedTime = blockTimestamp().sub(startTimestamp);
    uint256 elapsedMonths = elapsedTime.div(SECONDS_PER_MONTH);
    if (elapsedMonths < cliffInMonths) {
      return 0;
    }
    // If over vesting duration, all tokens vested
    if (elapsedMonths >= durationInMonths) {
      return token.balanceOf(address(this));
    } else {
      uint256 currentBalance = token.balanceOf(address(this));
      uint256 totalBalance = currentBalance.add(released);

      uint256 vested = totalBalance.mul(elapsedMonths).div(durationInMonths);
      uint256 unreleased = vested.sub(released);

      // currentBalance can be 0 in case of vesting being revoked earlier.
      return Math.min(currentBalance, unreleased);
    }
  }

  function blockTimestamp() public view virtual returns (uint256) {
    return block.timestamp;
  }
}

