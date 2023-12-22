// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
import "./Ownable.sol";
import "./ERC20.sol";
import "./BalancerInterfaces.sol";

contract PoolController is Ownable {
    address pool;

    constructor() {}

    // msg.sender is BalancerManager, function is public because owner=deployer
    function init(address pool_) public {
        require(pool == address(0), "Already initialized");
        pool = pool_;

        IManagedPool(pool).addAllowedAddress(msg.sender);
    }

    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        IERC20[] calldata tokens,
        uint256[] calldata endWeights
    ) external virtual onlyOwner {
        IManagedPool(pool).updateWeightsGradually(
            startTime,
            endTime,
            tokens,
            endWeights
        );
    }

    function updateSwapFeeGradually(
        uint256 startTime,
        uint256 endTime,
        uint256 startSwapFeePercentage,
        uint256 endSwapFeePercentage
    ) external onlyOwner {
        IManagedPool(pool).updateSwapFeeGradually(
            startTime,
            endTime,
            startSwapFeePercentage,
            endSwapFeePercentage
        );
    }

    function setSwapEnabled(bool swapEnabled) external virtual onlyOwner {
        IManagedPool(pool).setSwapEnabled(swapEnabled);
    }

    function setMustAllowlistLPs(
        bool mustAllowlistLPs
    ) external virtual onlyOwner {
        IManagedPool(pool).setMustAllowlistLPs(mustAllowlistLPs);
    }

    function addAllowedAddress(address member) external virtual onlyOwner {
        IManagedPool(pool).addAllowedAddress(member);
    }

    function removeAllowedAddress(address member) external virtual onlyOwner {
        IManagedPool(pool).removeAllowedAddress(member);
    }

    function collectAumManagementFees() external onlyOwner returns (uint256) {
        return IManagedPool(pool).collectAumManagementFees();
    }

    function withdrawCollectedManagementFees(
        address recipient
    ) external virtual onlyOwner {
        IERC20(pool).transfer(recipient, IERC20(pool).balanceOf(address(this)));
    }

    function setManagementAumFeePercentage(
        uint256 managementAumFeePercentage
    ) external virtual onlyOwner returns (uint256) {
        return
            IManagedPool(pool).setManagementAumFeePercentage(
                managementAumFeePercentage
            );
    }

    function addToken(
        IERC20 tokenToAdd,
        address assetManager,
        uint256 tokenToAddNormalizedWeight,
        uint256 mintAmount,
        address recipient
    ) external virtual onlyOwner {
        return
            IManagedPool(pool).addToken(
                tokenToAdd,
                assetManager,
                tokenToAddNormalizedWeight,
                mintAmount,
                recipient
            );
    }

    function removeToken(
        IERC20 tokenToRemove,
        uint256 burnAmount,
        address sender
    ) external virtual onlyOwner {
        return
            IManagedPool(pool).removeToken(tokenToRemove, burnAmount, sender);
    }
}

