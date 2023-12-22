// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";
import { IJonesStaker } from "./JonesStaker.sol";
import { IPendingRewards } from "./PendingRewards.sol";

interface IRewardsDistro {
  function updateInfo()
    external
    view
    returns (
      uint80 pls_,
      uint80 plsDpx_,
      uint80 plsJones_,
      uint80 pendingJonesLessFee_
    );

  function sendRewards(
    address _to,
    uint128 _plsAmt,
    uint128 _plsDpxAmt,
    uint128 _plsJonesAmt,
    uint128 _jonesAmt
  ) external;

  function harvestFromUnderlyingFarm() external;
}

contract PlsJonesRewardsDistro is IRewardsDistro, Ownable {
  IJonesStaker public immutable staker;
  IPendingRewards public immutable pendingRewards;

  IERC20 public immutable pls;
  IERC20 public immutable plsDpx;
  IERC20 public immutable plsJones;
  IERC20 public immutable jones;

  address public plutusChef;
  address public rewardsController;
  uint80 public plsPerSecond;
  uint80 public plsDpxPerSecond;
  uint80 public plsJonesPerSecond;

  constructor(
    address _pendingRewards,
    address _staker,
    address _pls,
    address _plsDpx,
    address _plsJones,
    address _jones
  ) {
    pendingRewards = IPendingRewards(_pendingRewards);
    staker = IJonesStaker(_staker);
    pls = IERC20(_pls);
    plsDpx = IERC20(_plsDpx);
    plsJones = IERC20(_plsJones);
    jones = IERC20(_jones);

    rewardsController = msg.sender;
  }

  function sendRewards(
    address _to,
    uint128 _plsAmt,
    uint128 _plsDpxAmt,
    uint128 _plsJonesAmt,
    uint128 _jonesAmt
  ) external {
    if (msg.sender != plutusChef) revert UNAUTHORIZED();

    if (isNotZero(_plsAmt)) {
      _safeTokenTransfer(pls, _to, _plsAmt);
    }

    // Treasury yields
    if (isNotZero(_plsDpxAmt) || isNotZero(_plsJonesAmt)) {
      _safeTokenTransfer(plsDpx, _to, _plsDpxAmt);
      _safeTokenTransfer(plsJones, _to, _plsJonesAmt);
    }

    // Underlying yields
    if (isNotZero(_jonesAmt)) {
      _safeTokenTransfer(jones, _to, _jonesAmt);
    }
  }

  function harvestFromUnderlyingFarm() external {
    if (msg.sender != plutusChef) revert UNAUTHORIZED();
    staker.harvest();
  }

  /** VIEWS */

  /**
  Returns emissions of all the yield sources for frontend
 */
  function getEmissions()
    external
    view
    returns (
      uint80 pls_,
      uint80 plsDpx_,
      uint80 plsJones_,
      uint80 jones_
    )
  {
    // PLS emissions
    pls_ = plsPerSecond;

    // Treasury yield
    plsDpx_ = plsDpxPerSecond;
    plsJones_ = plsJonesPerSecond;

    // Underlying farm yield less fee
    jones_ = uint80(staker.jonesPerSecondLessFee());
  }

  /**
    Info needed for PlutusChef updates.
   */
  function updateInfo()
    external
    view
    returns (
      uint80 pls_,
      uint80 plsDpx_,
      uint80 plsJones_,
      uint80 pendingJonesLessFee_
    )
  {
    // PLS emissions
    pls_ = plsPerSecond;

    // Treasury yield
    plsDpx_ = plsDpxPerSecond;
    plsJones_ = plsJonesPerSecond;

    // Pending Jones
    pendingJonesLessFee_ = uint80(pendingRewards.pendingJonesLessFee());
  }

  /** PRIVATE FUNCTIONS */
  function isNotZero(uint256 _num) private pure returns (bool result) {
    assembly {
      result := gt(_num, 0)
    }
  }

  function isZero(uint256 _num) private pure returns (bool result) {
    assembly {
      result := iszero(_num)
    }
  }

  function _safeTokenTransfer(
    IERC20 _token,
    address _to,
    uint256 _amount
  ) private {
    uint256 bal = _token.balanceOf(address(this));

    if (_amount > bal) {
      _token.transfer(_to, bal);
    } else {
      _token.transfer(_to, _amount);
    }
  }

  /** CONTROLLER FUNCTIONS */

  function _isRewardsController() private view {
    if (msg.sender != rewardsController) revert UNAUTHORIZED();
  }

  function updatePlsEmission(uint80 _newPlsRate) external {
    _isRewardsController();
    plsPerSecond = _newPlsRate;
  }

  function updatePlsDpxEmissions(uint80 _newPlsDpxRate) external {
    _isRewardsController();
    plsDpxPerSecond = _newPlsDpxRate;
  }

  function updatePlsJonesEmissions(uint80 _newPlsJonesRate) external {
    _isRewardsController();
    plsJonesPerSecond = _newPlsJonesRate;
  }

  /** OWNER FUNCTIONS */

  /**
    Owner can retrieve stuck funds
   */
  function retrieve(IERC20 token) external onlyOwner {
    if (isNotZero(address(this).balance)) {
      payable(owner()).transfer(address(this).balance);
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  function setPlutusChef(address _newPlutusChef) external onlyOwner {
    plutusChef = _newPlutusChef;
  }

  function setRewardsController(address _newController) external onlyOwner {
    rewardsController = _newController;
  }

  error UNAUTHORIZED();
}

