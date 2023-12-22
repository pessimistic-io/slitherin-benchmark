// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import { IFeeClaimer } from "./interfaces.sol";

interface IPlsDpxRewardsDistroV2 {
  function sendRewards(
    address _to,
    uint128 _plsAmt,
    uint128 _plsDpxAmt,
    uint128 _plsJonesAmt,
    uint128 _dpxAmt
  ) external;

  function getEmissions()
    external
    view
    returns (
      uint80 pls_,
      uint80 plsDpx_,
      uint80 plsJones_,
      uint256 pendingDpxLessFee_
    );

  function harvest() external;
}

contract PlsDpxRewardsDistroV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable, IPlsDpxRewardsDistroV2 {
  IERC20 public constant pls = IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F);
  IERC20 public constant plsDpx = IERC20(0xF236ea74B515eF96a9898F5a4ed4Aa591f253Ce1);
  IERC20 public constant plsJones = IERC20(0xe7f6C3c1F0018E4C08aCC52965e5cbfF99e34A44);
  IERC20 public constant dpx = IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);

  IFeeClaimer public constant FEE_CLAIMER = IFeeClaimer(0x4Ed6bB938eE0ca593669bfC5276091ff75d3d3f0);

  address public plutusChef;
  address public rewardsController;

  uint80 public plsPerSecond;
  uint80 public plsDpxPerSecond;
  uint80 public plsJonesPerSecond;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    rewardsController = msg.sender;
  }

  function harvest() external {
    if (msg.sender != plutusChef) revert UNAUTHORIZED();
    FEE_CLAIMER.harvest();
  }

  function sendRewards(
    address _to,
    uint128 _plsAmt,
    uint128 _plsDpxAmt,
    uint128 _plsJonesAmt,
    uint128 _dpxAmt
  ) external {
    if (msg.sender != plutusChef) revert UNAUTHORIZED();

    if (isNotZero(_plsAmt)) {
      _safeTokenTransfer(pls, _to, _plsAmt);
    }

    // Treasury yields
    if (isNotZero(_plsDpxAmt)) {
      _safeTokenTransfer(plsDpx, _to, _plsDpxAmt);
    }

    if (isNotZero(_plsJonesAmt)) {
      _safeTokenTransfer(plsJones, _to, _plsJonesAmt);
    }

    // Underlying yields
    if (isNotZero(_dpxAmt)) {
      _safeTokenTransfer(dpx, _to, _dpxAmt);
    }
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

  /** VIEWS */

  /**
  Returns emissions of all the yield sources
 */
  function getEmissions()
    external
    view
    returns (
      uint80 pls_,
      uint80 plsDpx_,
      uint80 plsJones_,
      uint256 pendingDpxLessFee_
    )
  {
    // PLS emissions
    pls_ = plsPerSecond;

    // Treasury yield
    plsDpx_ = plsDpxPerSecond;
    plsJones_ = plsJonesPerSecond;

    // veYield
    (pendingDpxLessFee_, ) = FEE_CLAIMER.pendingRewards();
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
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

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

