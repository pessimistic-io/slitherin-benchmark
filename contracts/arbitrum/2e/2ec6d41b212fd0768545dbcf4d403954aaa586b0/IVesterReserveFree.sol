// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IVesterReserveFree {
    function depositForAccount(address _account, uint256 _amount) external;

    function depositAmounts(address _account) external view returns (uint256);
    
    function claimForAccount(address _account, address _receiver) external returns (uint256);

    function transferVestableAmount(address _account, address _receiver) external;

    function transferredReserveFreeAmounts(address _account) external view returns (uint256);

    function reserveFreeDeduction(address _account) external view returns (uint256);

    function claimable(address _account) external view returns (uint256);

    function cumulativeClaimAmounts(address _account) external view returns (uint256);

    function claimedAmounts(address _account) external view returns (uint256);

    function getVestedAmount(address _account) external view returns (uint256);

    function bonusRewards(address _account) external view returns (uint256);

    function setBonusReward(address _account, uint256 _amount) external;

    function setBonusRewards(address[] memory  _account, uint256[] memory _amount) external;

    function getMaxVestableAmount(address _account) external view returns (uint256);
}
