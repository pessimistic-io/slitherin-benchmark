// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./Ownable.sol";
import "./AccessControl.sol";

import "./RyzeCreditToken.sol";

/**
 * @title Free Credit Token Giveaway Minter
 * @author Balance Capital
 */
contract RyzeCreditTokenGiveawayMinter is Ownable, AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    event DailyMintLimitSet(uint256 indexed tokenId, uint256 dailyMintLimit);
    event GaveAway(address indexed to, uint256 indexed tokenId, uint256 amount);

    struct HourlyMint {
        uint256 timestampFrom;
        uint256 timestampTo;
        uint256 amount;
    }

    RyzeCreditToken public ryzeCreditToken;

    mapping(uint256 => HourlyMint[]) public hourlyMintsByTokenId;
    // 24 hours mint limit
    mapping(uint256 => uint256) public dailyMintLimit;

    // user => total dispersed amount
    mapping(address => uint256) public userTotalDispersed;

    constructor(address _ryzeCreditToken) {
        ryzeCreditToken = RyzeCreditToken(_ryzeCreditToken);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
    }

    /// @notice Set daily mint limit
    /// @dev Only owner
    /// @param _dailyMintLimit The daily mint limit
    function setDailyMintLimit(uint256 _tokenId, uint256 _dailyMintLimit)
        external
        onlyOwner
    {
        dailyMintLimit[_tokenId] = _dailyMintLimit;
        emit DailyMintLimitSet(_tokenId, _dailyMintLimit);
    }

    /// @notice Send ryze credit tokens
    /// @param _to The recipient address
    /// @param _tokenId The token ID
    /// @param _amount The token amount to claim
    function giveaway(
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "MANAGER_ROLE_MISSING");

        require(
            lastDayMint(_tokenId) + _amount <= dailyMintLimit[_tokenId],
            "Daily mint limit"
        );

        userTotalDispersed[_to] += _amount;
        _updateHourlyMint(_tokenId, _amount);

        ryzeCreditToken.mint(_to, _tokenId, _amount);

        emit GaveAway(_to, _tokenId, _amount);
    }

    /// @notice Returns last 24 hours mint amount
    /// @return amount Last 24 hours mint amount
    function lastDayMint(uint256 _tokenId)
        public
        view
        returns (uint256 amount)
    {
        HourlyMint[] memory hourlyMints = hourlyMintsByTokenId[_tokenId];

        if (hourlyMints.length == 0) return 0;

        uint256 max = 0;
        if (hourlyMints.length >= 24) max = hourlyMints.length - 24;

        uint256 to = block.timestamp;
        uint256 from = to - 24 hours;
        for (uint256 i = max; i < hourlyMints.length; ++i) {
            if (
                hourlyMints[i].timestampFrom >= from &&
                hourlyMints[i].timestampFrom <= to
            ) {
                amount += hourlyMints[i].amount;
            }
        }

        return amount;
    }

    /// @notice Record hourly mint
    function _updateHourlyMint(uint256 tokenId, uint256 amount) internal {
        HourlyMint[] storage hourlyMints = hourlyMintsByTokenId[tokenId];

        uint256 currentTimestamp = block.timestamp;
        uint256 length = hourlyMints.length;
        if (length == 0) {
            hourlyMints.push(
                HourlyMint({
                    timestampFrom: currentTimestamp,
                    timestampTo: currentTimestamp + 1 hours,
                    amount: amount
                })
            );
            return;
        }

        HourlyMint storage lastHourlyMint = hourlyMints[length - 1];
        // update in existing interval
        if (
            lastHourlyMint.timestampFrom < currentTimestamp &&
            lastHourlyMint.timestampTo >= currentTimestamp
        ) {
            lastHourlyMint.amount += amount;
        } else {
            // create next interval if its continuous
            if (currentTimestamp <= lastHourlyMint.timestampTo + 1 hours) {
                hourlyMints.push(
                    HourlyMint({
                        timestampFrom: lastHourlyMint.timestampTo,
                        timestampTo: lastHourlyMint.timestampTo + 1 hours,
                        amount: amount
                    })
                );
            } else {
                hourlyMints.push(
                    HourlyMint({
                        timestampFrom: currentTimestamp,
                        timestampTo: currentTimestamp + 1 hours,
                        amount: amount
                    })
                );
            }
        }
    }

    /// @notice grants manager role to given _account
    /// @param _account manager contract
    function grantRoleManager(address _account) external {
        grantRole(MANAGER_ROLE, _account);
    }

    /// @notice revoke manager role to given _account
    /// @param _account manager contract
    function revokeRoleManager(address _account) external {
        revokeRole(MANAGER_ROLE, _account);
    }
}

