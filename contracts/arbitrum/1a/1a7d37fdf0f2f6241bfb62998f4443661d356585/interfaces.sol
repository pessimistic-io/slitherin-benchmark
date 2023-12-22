// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// IDPXVotingEscrow v1.0.0
interface IDPXVotingEscrow {
  function get_last_user_slope(address addr) external view returns (int128);

  function user_point_history__ts(address _addr, uint256 _idx) external view returns (uint256);

  function locked__end(address _addr) external view returns (uint256);

  function checkpoint() external;

  function deposit_for(address _addr, uint256 _value) external;

  function create_lock(uint256 _value, uint256 _unlock_time) external;

  function increase_amount(uint256 _value) external;

  function increase_unlock_time(uint256 _unlock_time) external;

  function withdraw() external;

  function balanceOf(address addr) external view returns (uint256);

  function balanceOfAtT(address addr, uint256 _t) external view returns (uint256);

  function balanceOfAt(address addr, uint256 _block) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function totalSupplyAtT(uint256 t) external view returns (uint256);

  function totalSupplyAt(uint256 _block) external view returns (uint256);

  function token() external view returns (address);

  function supply() external view returns (uint256);

  function locked(address addr) external view returns (int128 amount, uint256 end);

  function epoch() external view returns (uint256);

  function point_history(uint256 arg0)
    external
    view
    returns (
      int128 bias,
      int128 slope,
      uint256 ts,
      uint256 blk
    );

  function user_point_history(address arg0, uint256 arg1)
    external
    view
    returns (
      int128 bias,
      int128 slope,
      uint256 ts,
      uint256 blk
    );

  function user_point_epoch(address arg0) external view returns (uint256);

  function slope_changes(uint256 arg0) external view returns (int128);

  function controller() external view returns (address);

  function transfersEnabled() external view returns (bool);

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function version() external view returns (string memory);

  function decimals() external view returns (uint8);
}

interface IFeeDistro {
  function checkpoint() external;

  function getYield() external;

  function earned(address _account) external view returns (uint256);
}

interface IStaker {
  function stake(uint256) external;

  function release() external;

  function claimFees(
    address _distroContract,
    address _token,
    address _claimTo
  ) external returns (uint256);
}

interface IVoting {
  function vote_for_gauge_weights(address, uint256) external;
}

interface IFeeClaimer {
  function calcRewards(uint256 yield) external view returns (uint256 pendingRewardsLessFee, uint256 protocolFee);
}

