// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {BitMaps} from "./BitMaps.sol";
import {Vault} from "./Vault.sol";

interface IWaterFallDef {
    /**
     * @dev New Distribution Event.
     * @param sender Address that register a new distribution.
     * @param token ERC20 compatible token address that will be distributed.
     * @param merkleRoot Top node of a merkle tree structure.
     * @param startTime timestamp to accept claims in the distribution.
     * @param endTime timestamp to stop accepting claims in the distribution.
     */
    event NewDistribution(
        address indexed sender,
        address indexed token,
        bytes32 indexed merkleRoot,
        uint96 startTime,
        uint96 endTime
    );

    /**
     * @dev Claimed Event.
     * @param account Address that received tokens from claim function.
     * @param token ERC20 compatible token address that has be distributed.
     * @param amount Number of tokens transferred.
     */
    event Claimed(address account, address token, uint256 amount);

    event Withdrawn(address to);

    struct Config {
        IERC20Upgradeable token;
        bool configured;
        uint88 startTime;
        Vault tokensProvider;
        uint96 endTime;
        BitMaps.BitMap claimed;
    }

    error AlreadyClaimed();
    error InvalidClaimTime();
    error InvalidProof();
}

interface IWaterFall is IWaterFallDef {}

