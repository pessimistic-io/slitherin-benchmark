// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
pragma abicoder v2;

import "./AccessControlEnumerable.sol";
import "./IPriceConsumer.sol";

interface IFeedRegistryInterface {
    function latestRoundData(address base, address quote)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract ChainlinkPriceConsumer is IPriceConsumer, AccessControlEnumerable {
    // Fiat currencies follow https://en.wikipedia.org/wiki/ISO_4217
    address private constant _USD = address(840);
    address private _registry;

    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    mapping(address => uint256) private _tokenPrice;
    mapping(address => uint256) private _tokenTimestamp;
    mapping(address => address) private _feed;

    /**
     * Network: Ethereum Mainnet
     * Feed Registry: 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf
     */
    constructor(address registry) {
        _registry = registry;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function fetchPriceInUSD(address token, uint256 minTimestamp) external override onlyRole(ORACLE_MANAGER_ROLE) {
        if (_tokenTimestamp[token] >= minTimestamp) return;
        int256 price = 0;
        uint256 timeStamp = 0;
        // If we don't have a feed available for a given token, try the registry if available
        if (_feed[token] != address(0)) {
            (, price, , timeStamp, ) = IFeedRegistryInterface(_feed[token]).latestRoundData(token, _USD);
        } else if (_registry != address(0)) {
            (, price, , timeStamp, ) = IFeedRegistryInterface(_registry).latestRoundData(token, _USD);
        } else return;
        if (timeStamp < minTimestamp) return;
        _tokenPrice[token] = price >= 0 ? uint256(price) : 0;
        _tokenTimestamp[token] = timeStamp;
    }

    function getPriceInUSD(address token) external view override returns (uint256, uint256) {
        return (_tokenPrice[token], _tokenTimestamp[token]);
    }

    function updateFeed(address token, address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _feed[token] = feed;
    }
}

