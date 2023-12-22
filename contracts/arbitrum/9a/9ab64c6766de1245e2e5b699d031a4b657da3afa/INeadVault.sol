// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "./IERC20Upgradeable.sol";

interface IVault {
    function initialize( 
        address admin,
        address setter,
        address pauser,
        address asset_,
        string memory name_,
        string memory symbol_,
        address pool_,
        address _ram,
        address _neadram,
        address _router,
        address _rewarder,
        address _lp
    ) external;

     function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256);
    function setAddresses(
        address _Router,
        address _Locker,
        address _NFTHolder,
        address Multi,
        address _Lp
    ) external;
 function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);

     function getDepositToken() 
     external view returns (address depositToken);

      function pendingRewards(
          address user,
           address reward) 
           external view returns (uint256 pending);

  function claim(
      address user, 
      bool lp) 
      external; 
}
