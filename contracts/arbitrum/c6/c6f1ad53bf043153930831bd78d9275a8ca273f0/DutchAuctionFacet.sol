// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IStrategy.sol";

import "./IDutchAuctionFacet.sol";

import "./FullMath.sol";

contract DutchAuctionFacet is IDutchAuctionFacet {
    uint256 public constant Q96 = 2 ** 96;

    bytes32 internal constant STORAGE_POSITION = keccak256("mellow.contracts.auction.storage");

    function contractStorage() internal pure returns (IDutchAuctionFacet.Storage storage ds) {
        bytes32 position = STORAGE_POSITION;

        assembly {
            ds.slot := position
        }
    }

    function updateAuctionParams(
        uint32 duration,
        uint256 startCoefficientX96,
        uint256 endCoefficientX96,
        address strategy
    ) external {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        IDutchAuctionFacet.Storage storage ds = contractStorage();
        require(!ds.isStarted);
        ds.duration = duration;
        ds.endCoefficientX96 = endCoefficientX96;
        ds.startCoefficientX96 = startCoefficientX96;
        ds.strategy = strategy;
    }

    function startAuction() external {
        IDutchAuctionFacet.Storage storage ds = contractStorage();
        require(!ds.isStarted && IStrategy(ds.strategy).canStartAuction());

        ds.startTimestamp = block.timestamp;
        ds.isStarted = true;
    }

    function stopAuction() external {
        IDutchAuctionFacet.Storage storage ds = contractStorage();
        require(ds.isStarted && IStrategy(ds.strategy).canStopAuction());
        ds.isStarted = false;
    }

    function checkTvlAfterRebalance(uint256 tvlBefore, uint256 tvlAfter) external view returns (bool) {
        IDutchAuctionFacet.Storage memory ds = contractStorage();
        uint256 timestamp = block.timestamp;
        uint256 coefficientX96;
        if (timestamp >= ds.startTimestamp + ds.duration) {
            coefficientX96 = ds.endCoefficientX96;
        } else {
            coefficientX96 =
                FullMath.mulDiv(
                    timestamp - ds.startTimestamp,
                    ds.startCoefficientX96 - ds.endCoefficientX96,
                    ds.duration
                ) +
                ds.endCoefficientX96;
        }
        return FullMath.mulDiv(tvlBefore, coefficientX96, Q96) <= tvlAfter;
    }

    function auctionParams()
        external
        pure
        returns (
            uint256 startCoefficientX96,
            uint256 endCoefficientX96,
            uint32 duration,
            uint256 startTimestamp,
            bool isStarted,
            address strategy
        )
    {
        IDutchAuctionFacet.Storage memory ds = contractStorage();
        startCoefficientX96 = ds.startCoefficientX96;
        endCoefficientX96 = ds.endCoefficientX96;
        duration = ds.duration;
        startTimestamp = ds.startTimestamp;
        isStarted = ds.isStarted;
        strategy = ds.strategy;
    }

    function finishAuction() external {
        require(msg.sender == address(this));
        IDutchAuctionFacet.Storage storage ds = contractStorage();
        ds.isStarted = false;
    }
}

