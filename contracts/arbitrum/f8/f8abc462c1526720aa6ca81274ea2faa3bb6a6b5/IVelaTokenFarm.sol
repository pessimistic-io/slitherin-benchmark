// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVelaTokenFarm {
    function depositVesting(uint256 _amount) external;
    function withdrawVesting() external;
    function withdrawEsvela(uint256 _amount) external;
    function depositVlp(uint256 _amount) external;
    function withdrawVlp(uint256 _amount) external;
    function getStakedVLP(address _account) external view returns (uint256, uint256);
    function claimable(address _account) external returns (uint256);
    function harvestMany(bool _vela,bool _esvela,bool _vlp,bool _vesting) external;
}
