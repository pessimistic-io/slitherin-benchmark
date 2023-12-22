//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";

import "./BalancerCrystalExchangeContracts.sol";

contract BalancerCrystalExchange is Initializable, BalancerCrystalExchangeContracts {

    using SafeERC20Upgradeable for ISLP;

    function initialize() external initializer {
        BalancerCrystalExchangeContracts.__BalancerCrystalExchangeContracts_init();
    }

    function setBalancerCrystalId(uint256 _balancerCrystalId) external onlyAdminOrOwner {
        balancerCrystalId = _balancerCrystalId;
    }

    function setDAOAddress(address _daoAddress) external onlyAdminOrOwner {
        daoAddress = _daoAddress;
    }

    function exchangeSLPForBalancerCrystals(
        uint256 _amount)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(daoAddress != address(0), "BalancerCrystalExchange: DAO address not set");
        require(_amount > 0, "BalancerCrystalExchange: Amount is 0");
        require(_amount % 10**18 == 0, "BalancerCrystalExchange: Must be an integer amount of SLP");
        require(balancerCrystalId != 0, "BalancerCrystalExchange: Balancer Crystal ID is 0");

        // 1 for 1 slp (10**18) to balancer crystals.

        slp.safeTransferFrom(msg.sender, daoAddress, _amount);

        uint256 _balancerCrystalAmount = _amount / 10**18;

        balancerCrystal.mint(msg.sender, balancerCrystalId, _balancerCrystalAmount);
    }
}
