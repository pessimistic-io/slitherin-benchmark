// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.9;

import "./Initializable.sol";

import "./IStakeERC20.sol";
import "./IStakeERC20Factory.sol";
import "./Adminable.sol";
import "./DuetTransparentUpgradeableProxy.sol";

contract StakeERC20Factory is IStakeERC20Factory, Initializable, Adminable {
    mapping(address => address) public tokenToStakeMapping;
    mapping(address => address) public stakeToTokenMapping;
    address[] public stakeRepositoryAddresses;
    address public stakeImplementation;

    event StakeImplementationUpdated(address implementation, address previousImplementation);
    event StakeERC20RepositoryCreated(address tokenAddress, address stakeRpositoryAddress);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin_) public initializer {
        _setAdmin(admin_);
    }

    function setStakeImplementation(address impl_, bool upgradeDeployed_) external onlyAdmin {
        emit StakeImplementationUpdated(impl_, stakeImplementation);
        stakeImplementation = impl_;
        if (!upgradeDeployed_) {
            return;
        }
        for (uint256 i = 0; i < stakeRepositoryAddresses.length; i++) {
            DuetTransparentUpgradeableProxy(payable(stakeRepositoryAddresses[i])).upgradeTo(impl_);
        }
    }

    function createStakeRepository(
        address tokenAddress_,
        address rewardTokenAddress_
    ) external onlyAdmin returns (address stakeERC20Address) {
        address proxyAdmin = address(this);
        require(stakeImplementation != address(0), "StakeERC20Factory: Invalid StakeERC20 implementation");
        require(
            tokenToStakeMapping[tokenAddress_] == address(0),
            "StakeERC20Factory:This token's Stake Repository has already been set"
        );
        bytes memory proxyData;
        DuetTransparentUpgradeableProxy proxy = new DuetTransparentUpgradeableProxy(
            stakeImplementation,
            proxyAdmin,
            proxyData
        );
        stakeERC20Address = address(proxy);

        IStakeERC20(stakeERC20Address).initialize(address(this), tokenAddress_, rewardTokenAddress_);

        stakeRepositoryAddresses.push(stakeERC20Address);
        tokenToStakeMapping[tokenAddress_] = stakeERC20Address;
        stakeToTokenMapping[stakeERC20Address] = tokenAddress_;

        emit StakeERC20RepositoryCreated(tokenAddress_, stakeERC20Address);
    }
}

