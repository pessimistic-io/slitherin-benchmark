// SPDX-License-Identifier: MIT

pragma solidity >0.6.12;

interface IBoardroom {
    function totalSupply() external view returns (uint);

    function balanceOf(address _director) external view returns (uint);

    function earned(address _director) external view returns (uint);

    function canWithdraw(address _director) external view returns (bool);

    function canClaimReward(address _director) external view returns (bool);

    function epoch() external view returns (uint);

    function nextEpochPoint() external view returns (uint);

    function getArbiTenPrice() external view returns (uint);

    function setOperator(address _operator) external;

    function setReserveFund(address _reserveFund) external;

    function setStakeFee(uint _stakeFee) external;

    function setWithdrawFee(uint _withdrawFee) external;

    function setLockUp(uint _withdrawLockupEpochs, uint _rewardLockupEpochs) external;

    function stake(uint _amount) external;

    function withdraw(uint _amount) external;

    function exit() external;

    function claimReward() external;

    function allocateSeigniorage(uint _amount) external;

    function governanceRecoverUnsupported(address _token, uint _amount, address _to) external;
}

