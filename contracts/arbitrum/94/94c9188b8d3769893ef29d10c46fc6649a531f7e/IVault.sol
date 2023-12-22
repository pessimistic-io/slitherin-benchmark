// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface IVault {
   //  uint256 public totalShares; 
    function adjustTokenShares(uint256 _amount) external view returns(uint256);
    function getMyShares(address adr) external view returns(uint256);
    function giveAdjustTokenShares(address _user, uint256 _amount) external;
}

interface IVaultMiner {
   //  uint256 public totalShares; 
   function getTotalShares() external view returns(uint256);
   function COST_FOR_SHARE() external returns(uint256);
   function giveShares(address _addr, uint256 _amount, bool _forceClaim) external;
   function removeShares(address _addr, uint256 _amount) external;
   function getMyShares(address adr) external view returns(uint256);

   function setCurrentMultiplier(
     address _user, 
     uint256 _nftId, 
     uint256 _lifetime, 
     uint256 _startTime, 
     uint256 _endTime, 
     uint256 _multiplier
   ) external;

   function vaultClaimWorkers(address addr, address ref) external;

   function isInitialized() external view returns(bool);
   function getLastReset(address _addr) external view returns(uint256);

}
