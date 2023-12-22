pragma solidity ^0.7.6;

import "./IUniswapV3Pool.sol";
import "./TransferHelper.sol";
import "./IUniswapV3FlashCallback.sol";

contract DonationFlashSwap is IUniswapV3FlashCallback {
    IUniswapV3Pool public immutable pool;

    struct Donation {
        uint256 blockNumber;
        uint256 amount0;
        uint256 amount1;
    }

    Donation[] public donations;

    event DonationMade(
        address donor,
        uint256 amount0,
        uint256 amount1,
        uint256 blockNumber
    );

    constructor(IUniswapV3Pool _pool) {
        pool = _pool;
    }

    function donate(uint256 amount0Donation, uint256 amount1Donation) external {
        bytes memory data = abi.encode(amount0Donation, amount1Donation);
        pool.flash(address(this), 1, 1, data);
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        require(msg.sender == address(pool), "Invalid pool");

        (uint256 amount0Donation, uint256 amount1Donation) = abi.decode(
            data,
            (uint256, uint256)
        );

        uint256 amount0Owed = fee0 + 1; // Adding 1 for the borrowed amount
        uint256 amount1Owed = fee1 + 1; // Adding 1 for the borrowed amount

        TransferHelper.safeTransfer(
            pool.token0(),
            address(pool),
            amount0Owed + amount0Donation
        );
        TransferHelper.safeTransfer(
            pool.token1(),
            address(pool),
            amount1Owed + amount1Donation
        );

        donations.push(
            Donation(block.number, amount0Donation, amount1Donation)
        );
        emit DonationMade(
            msg.sender,
            amount0Donation,
            amount1Donation,
            block.number
        );
    }

    function getDonationsSince(
        uint256 sinceBlock
    ) public view returns (uint256 totalAmount0, uint256 totalAmount1) {
        for (uint256 i = 0; i < donations.length; i++) {
            if (donations[i].blockNumber >= sinceBlock) {
                totalAmount0 += donations[i].amount0;
                totalAmount1 += donations[i].amount1;
            }
        }
        return (totalAmount0, totalAmount1);
    }
}

