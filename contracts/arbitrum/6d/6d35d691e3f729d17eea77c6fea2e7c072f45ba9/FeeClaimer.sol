// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import { IStaker, IFeeDistro, IFeeClaimer } from "./interfaces.sol";

contract FeeClaimer is Initializable, OwnableUpgradeable, UUPSUpgradeable, IFeeClaimer {
  uint256 private constant FEE_DIVISOR = 1e4;
  IERC20 public constant REWARD_TOKEN = IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);
  address public constant STAKER = 0x6dE5BEc59ed2575a799f2aC0A0AeaAaf59E61c3D;
  IFeeDistro public constant UNDERLYING_FARM = IFeeDistro(0xCBBFB7e0E6782DF0d3e91F8D785A5Bf9E8d9775F);

  uint32 public fee; // fee in bp
  address public feeCollector;
  address public rewardsDistro;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    fee = 1200;
  }

  function harvest() external {
    if (msg.sender != rewardsDistro) revert UNAUTHORIZED();

    uint256 yield = IStaker(STAKER).claimFees(address(UNDERLYING_FARM), address(REWARD_TOKEN), address(this));

    if (isNotZero(yield)) {
      unchecked {
        uint256 protocolFee = (yield * fee) / FEE_DIVISOR;
        REWARD_TOKEN.transfer(feeCollector, protocolFee);

        uint256 pendingRewardsLessFee = yield - protocolFee;
        REWARD_TOKEN.transfer(rewardsDistro, pendingRewardsLessFee);
        emit RewardsClaimed(pendingRewardsLessFee, protocolFee);
      }
    }
  }

  /** VIEWS */
  function pendingRewards() external view returns (uint256 pendingRewardsLessFee, uint256 protocolFee) {
    uint256 yield = UNDERLYING_FARM.earned(STAKER);

    unchecked {
      protocolFee = (yield * fee) / FEE_DIVISOR;
      pendingRewardsLessFee = yield - protocolFee;
    }
  }

  /** CHECKS */
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

  function setFee(uint32 _fee) external onlyOwner {
    if (_fee > FEE_DIVISOR) {
      revert INVALID_FEE();
    }

    emit FeeChanged(_fee, fee);
    fee = _fee;
  }

  function setFeeCollector(address _newFeeCollector) external onlyOwner {
    emit FeeCollectorChanged(_newFeeCollector, feeCollector);
    feeCollector = _newFeeCollector;
  }

  function setRewardsDistro(address _newRewardsDistro) external onlyOwner {
    emit RewardsDistroChanged(_newRewardsDistro, rewardsDistro);
    rewardsDistro = _newRewardsDistro;
  }

  event FeeCollectorChanged(address indexed _new, address _old);
  event RewardsDistroChanged(address indexed _new, address _old);
  event FeeChanged(uint256 indexed _new, uint256 _old);
  event RewardsClaimed(uint256 _rewardsClaimedLessFee, uint256 _protocolFee);

  error INVALID_FEE();
  error UNAUTHORIZED();
}

