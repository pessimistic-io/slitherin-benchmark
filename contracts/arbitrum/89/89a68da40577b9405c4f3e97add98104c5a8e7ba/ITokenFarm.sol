// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @dev Interface of the VeDxp
 */
interface ITokenFarm {
    function depositVlp(uint256 _amount) external;

    function withdrawVlp(uint256 _amount) external;

    function harvestMany(bool _vela, bool _esvela, bool _vlp, bool _vesting) external;

    function claimable(address _account) external view returns (uint256);

    function esVELA() external view returns (address);

    function VELA() external view returns (address);

    function withdrawVesting() external;

    function depositVesting(uint256 _amount) external;

    function claim() external;

    function getStakedVLP(address _user) external view returns (uint256);
}

