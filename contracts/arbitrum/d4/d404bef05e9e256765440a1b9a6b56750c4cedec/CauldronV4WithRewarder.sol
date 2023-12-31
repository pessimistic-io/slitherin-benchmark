// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
import "./CauldronV4.sol";
import "./IRewarder.sol";
import "./BoringMath.sol";
import "./BoringRebase.sol";

contract CauldronV4WithRewarder is CauldronV4 {
    using RebaseLibrary for Rebase;
    using BoringMath for uint256;
    using BoringMath128 for uint128;

    IRewarder public rewarder;

    uint8 internal constant ACTION_HARVEST_FROM_REWARDER = 34;

    constructor(IBentoBoxV1 bentoBox_, IERC20 magicInternetMoney_) CauldronV4(bentoBox_, magicInternetMoney_) {}

    function setRewarder(IRewarder _rewarder) external {
        require(address(rewarder) == address(0));
        rewarder = _rewarder;
        blacklistedCallees[address(rewarder)] = true;
    }

    function _additionalCookAction(uint8 action, uint256 value, bytes memory data, uint256 value1, uint256 value2) internal virtual override returns (bytes memory, uint8) {
        if (action == ACTION_HARVEST_FROM_REWARDER) {
            address to = abi.decode(data, (address));
            uint256 overshoot = rewarder.harvest(to);
            return (abi.encode(overshoot), 1);
        }
    }

    function _afterAddCollateral(address user, uint256 collateralShare) internal override {
        rewarder.deposit(user, collateralShare);
    }

    function _afterRemoveCollateral(address user, uint256 collateralShare) internal override {
        rewarder.withdraw(user, collateralShare);
    }

    function _beforeUsersLiquidated(address[] memory users, uint256[] memory) internal virtual override {
        rewarder.harvestMultiple(users);
    }

    function _afterUserLiquidated(address user, uint256 collateralShare) internal override {
        rewarder.withdraw(user, collateralShare);
    }
}

