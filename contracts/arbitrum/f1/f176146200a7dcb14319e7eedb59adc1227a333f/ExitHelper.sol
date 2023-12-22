// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";

interface IOwnable {
  function transferOwnership(address newOwner) external;
}

interface IStaker is IOwnable {
  function exit() external;
}

interface IDpxStakingRewards {
  function balanceOf(address account) external view returns (uint256);

  function earned(address account) external view returns (uint256 DPXtokensEarned, uint256 RDPXtokensEarned);
}

interface IPlutusChef {
  function updateShares() external;
}

interface IRewardsDistro is IOwnable {
  function retrieve(IERC20 token) external;
}

contract ExitHelper is Ownable {
  IStaker private constant DPX_STAKER = IStaker(0xC046F44ED68014f048ECa0010A642749Ebe34b03);
  IDpxStakingRewards private constant DPX_STAKING_REWARDS =
    IDpxStakingRewards(0xc6D714170fE766691670f12c2b45C1f34405AAb6);

  IPlutusChef private constant PLUTUSCHEF = IPlutusChef(0x20DF4953BA19c74B2A46B6873803F28Bf640c1B5);
  IRewardsDistro private constant RWDISTRO = IRewardsDistro(0x38e517AB9edF86e8089633041ECb2E5Db00715aD);

  IERC20 private constant DPX = IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);
  IERC20 private constant RDPX = IERC20(0x32Eb7902D4134bf98A28b963D26de779AF92A212);

  function safeExit() external onlyOwner {
    uint256 _depositedDPX = DPX_STAKING_REWARDS.balanceOf(address(DPX_STAKER));

    (uint256 _DPXtokensEarned, uint256 _RDPXtokensEarned) = DPX_STAKING_REWARDS.earned(address(DPX_STAKER));

    DPX.transfer(address(DPX_STAKING_REWARDS), _depositedDPX + _DPXtokensEarned);
    RDPX.transfer(address(DPX_STAKING_REWARDS), _RDPXtokensEarned);

    DPX_STAKER.exit();

    _snapshotAndPullFromRewardsDistro();
  }

  function getAmountToTransfer() external view returns (uint256 _dpx, uint256 _rdpx) {
    uint256 _depositedDPX = DPX_STAKING_REWARDS.balanceOf(address(DPX_STAKER));

    (uint256 _DPXtokensEarned, uint256 _RDPXtokensEarned) = DPX_STAKING_REWARDS.earned(address(DPX_STAKER));

    uint256 dpxBuffer = 3e18;
    uint256 rdpxBuffer = 10e18;

    _dpx = _depositedDPX + _DPXtokensEarned + dpxBuffer;
    _rdpx = _RDPXtokensEarned + rdpxBuffer;
  }

  function safeExitWithoutPull() external onlyOwner {
    uint256 _depositedDPX = DPX_STAKING_REWARDS.balanceOf(address(DPX_STAKER));

    (uint256 _DPXtokensEarned, uint256 _RDPXtokensEarned) = DPX_STAKING_REWARDS.earned(address(DPX_STAKER));

    // uint256 dpxDust = 1 ether;
    // uint256 rdpxDust = 2 ether;

    DPX.transfer(address(DPX_STAKING_REWARDS), _depositedDPX + _DPXtokensEarned);
    RDPX.transfer(address(DPX_STAKING_REWARDS), _RDPXtokensEarned);

    DPX_STAKER.exit();
  }

  function retrieve(IERC20 token) external onlyOwner {
    token.transfer(owner(), token.balanceOf(address(this)));
  }

  function _snapshotAndPullFromRewardsDistro() internal {
    PLUTUSCHEF.updateShares();
    RWDISTRO.retrieve(DPX);
    RWDISTRO.retrieve(RDPX);
  }

  function snapshotAndPullFromRewardsDistro() external onlyOwner {
    RWDISTRO.retrieve(DPX);
    RWDISTRO.retrieve(RDPX);
  }

  function approve(
    IERC20 _token,
    address _address,
    uint256 _amount
  ) external onlyOwner {
    _token.approve(_address, _amount);
  }

  /// @dev transfer ownership of dpxStaker from this contract to deployer
  function setOwner() external onlyOwner {
    DPX_STAKER.transferOwnership(owner());
    RWDISTRO.transferOwnership(owner());
  }

  function execute(
    address _to,
    uint256 _value,
    bytes calldata _data
  ) external onlyOwner returns (bool, bytes memory) {
    (bool success, bytes memory result) = _to.call{ value: _value }(_data);
    return (success, result);
  }
}

