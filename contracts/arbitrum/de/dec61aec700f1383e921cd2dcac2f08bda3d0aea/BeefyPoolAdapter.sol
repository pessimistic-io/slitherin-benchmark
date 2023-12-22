// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./IPoolAdapter.sol";

// Interface of https://bscscan.com/address/0x97e5d50Fe0632A95b9cf1853E744E02f7D816677
interface IBeefyPool {
    function deposit(uint256) external;

    function withdraw(uint256 _shares) external;

    function withdrawAll() external;

    // Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
    function getPricePerFullShare() external view returns (uint256);

    // Staked token address
    function want() external view returns (address);

    // Staked token address for other pools
    function token() external view returns (address);
}

contract BeefyPoolAdapter is IPoolAdapter {
    function deposit(
        address pool,
        uint256 amount,
        bytes memory /* args */
    ) external {
        IBeefyPool(pool).deposit(amount);
    }

    function stakingBalance(
        address pool,
        bytes memory /* args */
    ) external view returns (uint256) {
        uint256 sharesBalance = IERC20Upgradeable(pool).balanceOf(address(this));

        // sharePrice has 18 decimals
        uint256 sharePrice = IBeefyPool(pool).getPricePerFullShare();
        return (sharesBalance * sharePrice) / 1e18;
    }

    function rewardBalances(address, bytes memory) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function withdraw(
        address pool,
        uint256 amount,
        bytes memory /* args */
    ) external {
        // sharePrice has 18 decimals
        uint256 sharePrice = IBeefyPool(pool).getPricePerFullShare();
        uint256 sharesAmount = (amount * 1e18) / sharePrice;
        IBeefyPool(pool).withdraw(sharesAmount);
    }

    function withdrawAll(
        address pool,
        bytes memory /* args */
    ) external {
        IBeefyPool(pool).withdrawAll();
    }

    function stakedToken(
        address pool,
        bytes memory /* args */
    ) external view returns (address) {
        return _token(pool);
    }

    function rewardTokens(address, bytes memory args) external pure returns (address[] memory) {
        return new address[](0);
    }

    function _token(address pool) private view returns (address) {
        bool success;
        bytes memory response;

        (success, response) = pool.staticcall(abi.encodeWithSelector(IBeefyPool.want.selector));
        if (success && response.length == 32) {
            return abi.decode(response, (address));
        }

        (success, response) = pool.staticcall(abi.encodeWithSelector(IBeefyPool.token.selector));
        if (success && response.length == 32) {
            return abi.decode(response, (address));
        }

        revert("incompatible contract");
    }
}

